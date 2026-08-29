require "test_helper"

# 인근 도서관 §5.3 — 시도코드 도출·토큰 완전일치 gu 필터·N컷·시간예산·분리 TTL 캐시·as_of.
class Library::NearbyAvailabilityTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  ISBN = "9788949140926".freeze

  # 네트워크 없는 스텁 서비스. holdings 는 nil(실패)/[]/배열을 그대로 돌려주고 호출 수를 센다.
  class StubService
    attr_reader :holdings_calls, :loan_calls, :loan_timeouts

    # 팬아웃이 병렬이라 카운터는 여러 스레드가 함께 만진다 — 뮤텍스로 보호한다.
    def initialize(available: true, holdings: [], loans: {}, loan_delay: 0,
                   slow_codes: [], slow_delay: 0)
      @available = available
      @holdings = holdings
      @loans = loans # code => { status:, fetched_at: }
      @loan_delay = loan_delay
      @slow_codes = slow_codes # 이 도서관들만 따로 느리게(예산 초과 시뮬레이션)
      @slow_delay = slow_delay
      @holdings_calls = 0
      @loan_calls = 0
      @loan_timeouts = [] # 서비스가 실제로 받은 read timeout 들
      @lock = Mutex.new
    end

    def available? = @available

    def libraries_holding(isbn13:, region:, page_size: 1000, timeout: nil)
      @holdings_calls += 1
      @holdings
    end

    def loan_status(lib_code:, isbn13:, timeout: nil)
      @lock.synchronize { @loan_calls += 1; @loan_timeouts << timeout }
      delay = @slow_codes.include?(lib_code) ? @slow_delay : @loan_delay
      sleep(delay) if delay.positive?
      @loans.fetch(lib_code, { status: :unknown, fetched_at: Time.current })
    end
  end

  def lib(code, address, name: nil)
    { code: code, name: name || "도서관#{code}", address: address,
      tel: "", homepage: "", latitude: "", longitude: "" }
  end

  def sample_book = Book.new(isbn: ISBN)

  def sample_school(region: "서울특별시교육청", gu: "노원구", address: "서울특별시 노원구 상계로 1")
    School.new(region: region, gu: gu, address: address)
  end

  def memory_cache = ActiveSupport::Cache::MemoryStore.new

  def build(service:, book: sample_book, school: sample_school, **opts)
    Library::NearbyAvailability.new(book: book, school: school, service: service,
                                    cache: memory_cache, **opts)
  end

  # --- 렌더 경로: 외부 HTTP 0 + 워밍 위임 ---
  #
  # 렌더가 정보나루를 직접 부르던 시절, 운영 실측은 libSrchByBook 9.5초 · bookExist 1콜
  # 7.9~35.5초였다. 5곳 순차면 101초다. 시간예산을 조이면 대부분이 "확인 필요"로 떨어지고
  # 늘리면 아이가 그만큼 기다린다 — 렌더 안에서 풀 수 있는 문제가 아니었다.
  # 그래서 `call` 은 **캐시만 읽는다.** 이 성질이 깨지면 요청이 다시 외부 API 에 묶인다.

  test "렌더 경로(call)는 외부 HTTP 를 한 번도 하지 않는다" do
    book = Book.create!(title: "근처책", author: "김저자", isbn: ISBN)
    school = School.create!(name: "근처초", region: "서울특별시교육청", gu: "노원구",
                            address: "서울특별시 노원구 상계로 1")
    stub = StubService.new(holdings: [ lib("A", "서울특별시 노원구 상계로 1") ])

    result = Library::NearbyAvailability.new(book: book, school: school, service: stub,
                                             cache: memory_cache).call

    assert_equal :warming, result.state
    assert_equal 0, stub.holdings_calls, "렌더는 소장 목록을 원격으로 부르지 않는다"
    assert_equal 0, stub.loan_calls, "렌더는 대출여부를 원격으로 부르지 않는다"
  end

  test "캐시 미스면 워밍 잡을 걸고 :warming 으로 즉시 돌아온다" do
    book = Book.create!(title: "워밍책", author: "김저자", isbn: ISBN)
    school = School.create!(name: "워밍초", region: "서울특별시교육청", gu: "노원구",
                            address: "서울특별시 노원구 상계로 1")
    availability = Library::NearbyAvailability.new(book: book, school: school,
                                                   service: StubService.new, cache: memory_cache)

    assert_enqueued_with(job: Library::NearbyLibrariesWarmJob, args: [ book.id, school.id ]) do
      assert_equal :warming, availability.call.state
    end
  end

  test "한 반이 같은 책을 동시에 열어도 워밍 잡은 1건이다(스탬피드 가드)" do
    book = Book.create!(title: "동시책", author: "김저자", isbn: ISBN)
    school = School.create!(name: "동시초", region: "서울특별시교육청", gu: "노원구",
                            address: "서울특별시 노원구 상계로 1")
    cache = memory_cache # 학생들이 같은 캐시를 공유한다
    render = -> { Library::NearbyAvailability.new(book: book, school: school,
                                                  service: StubService.new, cache: cache).call }

    5.times { assert_equal :warming, render.call.state }

    assert_enqueued_jobs 1, only: Library::NearbyLibrariesWarmJob
  end

  test "캐시가 다 차 있으면 렌더가 외부 콜 0 으로 :ok 를 낸다" do
    holdings = [ lib("A", "서울특별시 노원구 상계로 1") ]
    cache = memory_cache
    warmer = build(service: StubService.new(holdings: holdings,
                                            loans: { "A" => { status: :available, fetched_at: Time.current } }),
                   cache: cache)
    warmer.warm! # 워밍 잡이 하는 일

    reader = StubService.new(holdings: nil) # 렌더가 원격을 부르면 :error 로 드러난다
    result = build(service: reader, cache: cache).call

    assert_equal :ok, result.state
    assert_equal :available, result.libraries.first[:status]
    assert_equal 0, reader.holdings_calls
    assert_equal 0, reader.loan_calls
  end

  test "소장 목록만 캐시되고 대출여부가 비면 반쯤 채운 화면 대신 :warming 을 낸다" do
    # "확인 필요"가 섞인 화면을 내보내느니 잠깐 기다렸다 완성본을 보여 준다.
    book = Book.create!(title: "반쯤책", author: "김저자", isbn: ISBN)
    school = School.create!(name: "반쯤초", region: "서울특별시교육청", gu: "노원구",
                            address: "서울특별시 노원구 상계로 1")
    cache = memory_cache
    cache.write("nearby_holdings:v1:#{ISBN}:11", [ lib("A", "서울특별시 노원구 상계로 1") ])

    result = Library::NearbyAvailability.new(book: book, school: school,
                                             service: StubService.new, cache: cache).call

    assert_equal :warming, result.state
  end

  # --- state 분기 ---

  test ":no_key when the service is unavailable (offline / no key)" do
    result = build(service: StubService.new(available: false)).call
    assert_equal :no_key, result.state
  end

  test ":no_isbn when the book has no isbn (defensive)" do
    result = build(service: StubService.new, book: Book.new(isbn: nil)).call
    assert_equal :no_isbn, result.state
  end

  test ":no_location when the school is nil" do
    result = build(service: StubService.new, school: nil).call
    assert_equal :no_location, result.state
  end

  test ":no_location when neither region nor address resolves to a sido code" do
    unlocatable = School.new(region: "", address: "")
    result = build(service: StubService.new, school: unlocatable).call
    assert_equal :no_location, result.state
  end

  test ":error when the holdings call fails (nil, distinct from empty)" do
    result = build(service: StubService.new(holdings: nil)).warm!
    assert_equal :error, result.state
  end

  test ":none when the book is held nowhere in the sido" do
    result = build(service: StubService.new(holdings: [])).warm!
    assert_equal :none, result.state
  end

  # --- 상태 조합(criterion 1) ---

  test ":ok lists nearby libraries with per-library available/busy badges" do
    holdings = [ lib("A", "서울특별시 노원구 상계로 1"), lib("B", "서울특별시 노원구 월계로 2") ]
    loans = { "A" => { status: :available, fetched_at: Time.current },
              "B" => { status: :unavailable, fetched_at: Time.current } }
    result = build(service: StubService.new(holdings: holdings, loans: loans)).warm!

    assert_equal :ok, result.state
    assert_equal 2, result.libraries.size
    assert_equal :available, result.libraries.find { |l| l[:name] == "도서관A" }[:status]
    assert_equal :unavailable, result.libraries.find { |l| l[:name] == "도서관B" }[:status]
  end

  # --- 토큰 완전일치 gu 필터(criterion 9, include? 회귀 방지) ---

  test "token-exact gu filter excludes 대구 서구 vs 달서구 (substring would over-match)" do
    holdings = [ lib("A", "대구광역시 달서구 성서로 1") ]
    school = sample_school(region: "대구광역시교육청", gu: "서구")
    result = build(service: StubService.new(holdings: holdings), school: school).warm!
    assert_equal :none, result.state
  end

  test "token-exact gu filter excludes 부산 서구 vs 강서구" do
    holdings = [ lib("A", "부산광역시 강서구 명지로 1") ]
    school = sample_school(region: "부산광역시교육청", gu: "서구")
    result = build(service: StubService.new(holdings: holdings), school: school).warm!
    assert_equal :none, result.state
  end

  test "token-exact gu filter excludes 인천 동구 vs 남동구" do
    holdings = [ lib("A", "인천광역시 남동구 구월로 1") ]
    school = sample_school(region: "인천광역시교육청", gu: "동구")
    result = build(service: StubService.new(holdings: holdings), school: school).warm!
    assert_equal :none, result.state
  end

  test "token-exact gu filter keeps the exact-token match" do
    holdings = [ lib("A", "대구광역시 서구 국채보상로 1"), lib("B", "대구광역시 달서구 성서로 2") ]
    school = sample_school(region: "대구광역시교육청", gu: "서구")
    result = build(service: StubService.new(holdings: holdings), school: school).warm!

    assert_equal :ok, result.state
    assert_equal [ "도서관A" ], result.libraries.map { |l| l[:name] }
  end

  test "keeps all sido libraries when gu is nil (세종 single-tier)" do
    holdings = [ lib("A", "세종특별자치시 한누리대로 1"), lib("B", "세종특별자치시 조치원읍 2") ]
    # 세종 교육청명은 SIDO_BY_OFFICE 폐집합에 있어 region → 29, gu 는 nil(단층제).
    sejong = School.new(region: "세종특별자치시교육청", gu: nil, address: "세종특별자치시 한누리대로 1")
    result = build(service: StubService.new(holdings: holdings), school: sejong).warm!

    assert_equal :ok, result.state
    assert_equal 2, result.libraries.size
  end

  # --- N컷(criterion 10) ---

  test "caps the fan-out at max_libraries (bookExist calls <= 5)" do
    holdings = (1..7).map { |i| lib("L#{i}", "서울특별시 노원구 상계로 #{i}") }
    stub = StubService.new(holdings: holdings)
    result = build(service: stub).warm!

    assert_equal :ok, result.state
    assert_equal 5, result.libraries.size
    assert_operator stub.loan_calls, :<=, 5
    assert_equal 5, stub.loan_calls
  end

  # --- 시간예산 초과 → :unknown degrade(criterion 11) ---

  test "degrades statuses to :unknown when the time budget is exhausted (no infinite spinner)" do
    holdings = [ lib("A", "서울특별시 노원구 상계로 1"), lib("B", "서울특별시 노원구 월계로 2") ]
    stub = StubService.new(holdings: holdings)
    result = build(service: stub, time_budget: 0).warm!

    assert_equal :ok, result.state, "예산 초과여도 프레임은 완료 렌더된다"
    assert result.libraries.all? { |l| l[:status] == :unknown }
    assert_equal 0, stub.loan_calls, "예산 밖이면 bookExist 를 호출하지 않는다"
  end

  test "팬아웃이 병렬이라 총 소요가 콜 수에 비례해 늘지 않는다" do
    # 운영 실측(2026-08-29): bookExist 1콜이 7.9~35.5초다. 5곳 순차면 **합 101초**,
    # 동시에 쏘면 8.7초에 5곳 전부 실제 상태였다. 워밍 잡 안이라 요청을 막지는 않지만,
    # 순차로 두면 워밍 한 번이 2분 가까이 걸려 잡 큐를 잡아먹는다.
    holdings = %w[A B C D E].each_with_index.map { |c, i| lib(c, "서울특별시 노원구 길#{i} 1") }
    loans = holdings.to_h { |l| [ l[:code], { status: :available, fetched_at: Time.current } ] }
    stub = StubService.new(holdings: holdings, loans: loans, loan_delay: 0.3)

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = build(service: stub, time_budget: 3).warm!
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    assert_equal 5, stub.loan_calls
    assert result.libraries.all? { |l| l[:status] == :available },
           "5곳 모두 실제 상태를 받아야 한다(예산에 밀려 :unknown 으로 떨어지지 않는다)"
    assert_operator elapsed, :<, 1.0,
                    "순차였다면 5×0.3=1.5초를 넘겼을 것이다(실제 #{elapsed.round(2)}초)"
  end

  test "느린 도서관 한 곳이 나머지를 끌고 내려가지 않는다" do
    # 순차 시절의 핵심 문제 — 앞의 느린 한 곳이 예산을 다 먹으면 뒤가 전부 :unknown 이 됐다.
    holdings = [ lib("SLOW", "서울특별시 노원구 상계로 1"), lib("A", "서울특별시 노원구 월계로 2"),
                 lib("B", "서울특별시 노원구 한글비석로 3") ]
    stub = StubService.new(holdings: holdings, slow_codes: %w[SLOW], slow_delay: 2.0, loan_delay: 0.1,
                           loans: { "A" => { status: :available, fetched_at: Time.current },
                                    "B" => { status: :unavailable, fetched_at: Time.current } })

    result = build(service: stub, time_budget: 1).warm!
    by_name = result.libraries.to_h { |l| [ l[:name], l[:status] ] }

    assert_equal :unknown, by_name["도서관SLOW"], "예산 안에 못 들어온 곳만 강등된다"
    assert_equal :available, by_name["도서관A"], "느린 이웃 때문에 함께 죽지 않는다"
    assert_equal :unavailable, by_name["도서관B"]
  end

  test "캐시 히트는 예산이 바닥나도 :unknown 으로 떨어지지 않는다" do
    # 캐시 읽기는 시간을 쓰지 않는다. 예산은 원격 호출만 제한해야 한다.
    cache = memory_cache
    cache.write("book_loan:v1:A:#{ISBN}", { status: :available, fetched_at: Time.current })
    holdings = [ lib("A", "서울특별시 노원구 상계로 1") ]
    stub = StubService.new(holdings: holdings)

    result = Library::NearbyAvailability.new(book: sample_book, school: sample_school, service: stub,
                                             cache: cache, time_budget: 0).warm!

    assert_equal :available, result.libraries.first[:status], "캐시된 확정값은 예산과 무관하다"
    assert_equal 0, stub.loan_calls
  end

  # --- 분리 TTL 캐시 히트(criterion 12) ---

  test "holdings cache hit issues zero external holdings calls on re-query" do
    holdings = [ lib("A", "서울특별시 노원구 상계로 1") ]
    stub = StubService.new(holdings: holdings, loans: { "A" => { status: :available, fetched_at: Time.current } })
    availability = Library::NearbyAvailability.new(book: sample_book, school: sample_school, service: stub, cache: memory_cache)

    availability.warm!
    availability.warm!

    assert_equal 1, stub.holdings_calls, "동일 (isbn,region) 재조회는 소장 목록을 캐시에서 읽는다"
  end

  # --- 대출여부 캐시 정책: 확정값만 캐시, 일시 :unknown 은 재시도 ---

  test "caches a definitive loan status (one bookExist across a re-query)" do
    holdings = [ lib("A", "서울특별시 노원구 상계로 1") ]
    stub = StubService.new(holdings: holdings, loans: { "A" => { status: :available, fetched_at: Time.current } })
    cache = memory_cache
    availability = Library::NearbyAvailability.new(book: sample_book, school: sample_school, service: stub, cache: cache)

    availability.warm!
    availability.warm!

    assert_equal 1, stub.loan_calls, "확정값(available)은 15min 캐시되어 재조회 시 bookExist 를 다시 호출하지 않는다"
  end

  test "일시 :unknown 은 짧게만 기억한다 — 무한 워밍 루프도, 회복 억제도 피한다" do
    # 두 실패 사이의 균형점이다.
    #   · 아예 캐시하지 않으면 → 렌더가 그 도서관을 영원히 미스로 보고 :warming → 워밍 → :warming
    #     을 반복한다. 한 곳만 계속 느려도 섹션 전체가 안 뜬다(무한 워밍 루프).
    #   · 확정값처럼 15분 캐시하면 → 일시 오류가 회복돼도 15분간 "확인 필요"가 굳는다.
    # 그래서 UNKNOWN_LOAN_TTL(2분)만 기억한다.
    holdings = [ lib("A", "서울특별시 노원구 상계로 1") ]
    # loans 에 "A" 미지정 → StubService 기본이 :unknown(일시 오류 시뮬레이션).
    stub = StubService.new(holdings: holdings)
    cache = memory_cache
    availability = Library::NearbyAvailability.new(book: sample_book, school: sample_school, service: stub, cache: cache)

    availability.warm!
    availability.warm!
    assert_equal 1, stub.loan_calls, "직후 재워밍은 캐시를 읽어 루프를 만들지 않는다"

    travel(Library::NearbyAvailability::UNKNOWN_LOAN_TTL + 1.second) do
      availability.warm!
      assert_equal 2, stub.loan_calls, "짧은 TTL 이 지나면 다시 시도한다(회복 억제 방지)"
    end
  end

  test "확정값은 :unknown 보다 훨씬 오래 기억한다" do
    # :unknown TTL 이 지나도 확정값은 남아 있어야 한다 — 두 TTL 이 같아지면 15분 캐시의 의미가 없다.
    holdings = [ lib("A", "서울특별시 노원구 상계로 1") ]
    stub = StubService.new(holdings: holdings,
                           loans: { "A" => { status: :available, fetched_at: Time.current } })
    cache = memory_cache
    availability = Library::NearbyAvailability.new(book: sample_book, school: sample_school, service: stub, cache: cache)
    availability.warm!

    travel(Library::NearbyAvailability::UNKNOWN_LOAN_TTL + 1.second) do
      availability.warm!
      assert_equal 1, stub.loan_calls, "확정값(available)은 그대로 캐시에 남는다"
    end
  end

  # --- as_of = 가장 오래된 fetched_at(criterion 13, 15분 캐시 → "15분 기준") ---

  test "as_of is the oldest fetched_at so a 15-minute-old loan cache reads as 15 minutes, not 0" do
    fixed = Time.utc(2026, 7, 19, 12, 0, 0)
    fifteen_min_ago = fixed - 15.minutes
    cache = memory_cache
    cache.write("book_loan:v1:A:#{ISBN}", { status: :available, fetched_at: fifteen_min_ago })

    holdings = [ lib("A", "서울특별시 노원구 상계로 1") ]
    stub = StubService.new(holdings: holdings)
    availability = Library::NearbyAvailability.new(book: sample_book, school: sample_school, service: stub,
                                                   cache: cache, now: -> { fixed })
    result = availability.warm!

    assert_equal :ok, result.state
    assert_equal fifteen_min_ago, result.as_of, "as_of 는 캐시된 fetched_at(15분 전)이라야 한다"
    assert_equal 0, stub.loan_calls, "대출여부는 캐시 히트라 bookExist 를 호출하지 않는다"
  end
end
