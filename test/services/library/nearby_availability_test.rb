require "test_helper"

# 인근 도서관 §5.3 — 시도코드 도출·토큰 완전일치 gu 필터·N컷·시간예산·분리 TTL 캐시·as_of.
class Library::NearbyAvailabilityTest < ActiveSupport::TestCase
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
    result = build(service: StubService.new(holdings: nil)).call
    assert_equal :error, result.state
  end

  test ":none when the book is held nowhere in the sido" do
    result = build(service: StubService.new(holdings: [])).call
    assert_equal :none, result.state
  end

  # --- 상태 조합(criterion 1) ---

  test ":ok lists nearby libraries with per-library available/busy badges" do
    holdings = [ lib("A", "서울특별시 노원구 상계로 1"), lib("B", "서울특별시 노원구 월계로 2") ]
    loans = { "A" => { status: :available, fetched_at: Time.current },
              "B" => { status: :unavailable, fetched_at: Time.current } }
    result = build(service: StubService.new(holdings: holdings, loans: loans)).call

    assert_equal :ok, result.state
    assert_equal 2, result.libraries.size
    assert_equal :available, result.libraries.find { |l| l[:name] == "도서관A" }[:status]
    assert_equal :unavailable, result.libraries.find { |l| l[:name] == "도서관B" }[:status]
  end

  # --- 토큰 완전일치 gu 필터(criterion 9, include? 회귀 방지) ---

  test "token-exact gu filter excludes 대구 서구 vs 달서구 (substring would over-match)" do
    holdings = [ lib("A", "대구광역시 달서구 성서로 1") ]
    school = sample_school(region: "대구광역시교육청", gu: "서구")
    result = build(service: StubService.new(holdings: holdings), school: school).call
    assert_equal :none, result.state
  end

  test "token-exact gu filter excludes 부산 서구 vs 강서구" do
    holdings = [ lib("A", "부산광역시 강서구 명지로 1") ]
    school = sample_school(region: "부산광역시교육청", gu: "서구")
    result = build(service: StubService.new(holdings: holdings), school: school).call
    assert_equal :none, result.state
  end

  test "token-exact gu filter excludes 인천 동구 vs 남동구" do
    holdings = [ lib("A", "인천광역시 남동구 구월로 1") ]
    school = sample_school(region: "인천광역시교육청", gu: "동구")
    result = build(service: StubService.new(holdings: holdings), school: school).call
    assert_equal :none, result.state
  end

  test "token-exact gu filter keeps the exact-token match" do
    holdings = [ lib("A", "대구광역시 서구 국채보상로 1"), lib("B", "대구광역시 달서구 성서로 2") ]
    school = sample_school(region: "대구광역시교육청", gu: "서구")
    result = build(service: StubService.new(holdings: holdings), school: school).call

    assert_equal :ok, result.state
    assert_equal [ "도서관A" ], result.libraries.map { |l| l[:name] }
  end

  test "keeps all sido libraries when gu is nil (세종 single-tier)" do
    holdings = [ lib("A", "세종특별자치시 한누리대로 1"), lib("B", "세종특별자치시 조치원읍 2") ]
    # 세종 교육청명은 SIDO_BY_OFFICE 폐집합에 있어 region → 29, gu 는 nil(단층제).
    sejong = School.new(region: "세종특별자치시교육청", gu: nil, address: "세종특별자치시 한누리대로 1")
    result = build(service: StubService.new(holdings: holdings), school: sejong).call

    assert_equal :ok, result.state
    assert_equal 2, result.libraries.size
  end

  # --- N컷(criterion 10) ---

  test "caps the fan-out at max_libraries (bookExist calls <= 5)" do
    holdings = (1..7).map { |i| lib("L#{i}", "서울특별시 노원구 상계로 #{i}") }
    stub = StubService.new(holdings: holdings)
    result = build(service: stub).call

    assert_equal :ok, result.state
    assert_equal 5, result.libraries.size
    assert_operator stub.loan_calls, :<=, 5
    assert_equal 5, stub.loan_calls
  end

  # --- 시간예산 초과 → :unknown degrade(criterion 11) ---

  test "degrades statuses to :unknown when the time budget is exhausted (no infinite spinner)" do
    holdings = [ lib("A", "서울특별시 노원구 상계로 1"), lib("B", "서울특별시 노원구 월계로 2") ]
    stub = StubService.new(holdings: holdings)
    result = build(service: stub, time_budget: 0).call

    assert_equal :ok, result.state, "예산 초과여도 프레임은 완료 렌더된다"
    assert result.libraries.all? { |l| l[:status] == :unknown }
    assert_equal 0, stub.loan_calls, "예산 밖이면 bookExist 를 호출하지 않는다"
  end

  test "팬아웃이 병렬이라 총 소요가 콜 수에 비례해 늘지 않는다" do
    # 운영 실측: bookExist 1콜이 2.5~3초다. 순차면 5곳에 12.5초 + 소장 목록 = 14.4초로,
    # 계획서가 실측한 14.3초와 정확히 일치한다. 순차인 한 "빠른 화면"과 "실제 대출 상태" 중
    # 하나를 포기해야 하므로, 동시에 쏴서 총 소요를 **최장 1콜**로 만든다.
    holdings = %w[A B C D E].each_with_index.map { |c, i| lib(c, "서울특별시 노원구 길#{i} 1") }
    loans = holdings.to_h { |l| [ l[:code], { status: :available, fetched_at: Time.current } ] }
    stub = StubService.new(holdings: holdings, loans: loans, loan_delay: 0.3)

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = build(service: stub, time_budget: 3).call
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

    result = build(service: stub, time_budget: 1).call
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
                                             cache: cache, time_budget: 0).call

    assert_equal :available, result.libraries.first[:status], "캐시된 확정값은 예산과 무관하다"
    assert_equal 0, stub.loan_calls
  end

  # --- 분리 TTL 캐시 히트(criterion 12) ---

  test "holdings cache hit issues zero external holdings calls on re-query" do
    holdings = [ lib("A", "서울특별시 노원구 상계로 1") ]
    stub = StubService.new(holdings: holdings, loans: { "A" => { status: :available, fetched_at: Time.current } })
    availability = Library::NearbyAvailability.new(book: sample_book, school: sample_school, service: stub, cache: memory_cache)

    availability.call
    availability.call

    assert_equal 1, stub.holdings_calls, "동일 (isbn,region) 재조회는 소장 목록을 캐시에서 읽는다"
  end

  # --- 대출여부 캐시 정책: 확정값만 캐시, 일시 :unknown 은 재시도 ---

  test "caches a definitive loan status (one bookExist across a re-query)" do
    holdings = [ lib("A", "서울특별시 노원구 상계로 1") ]
    stub = StubService.new(holdings: holdings, loans: { "A" => { status: :available, fetched_at: Time.current } })
    cache = memory_cache
    availability = Library::NearbyAvailability.new(book: sample_book, school: sample_school, service: stub, cache: cache)

    availability.call
    availability.call

    assert_equal 1, stub.loan_calls, "확정값(available)은 15min 캐시되어 재조회 시 bookExist 를 다시 호출하지 않는다"
  end

  test "does not cache a transient :unknown loan status (re-queries so recovery is not suppressed)" do
    holdings = [ lib("A", "서울특별시 노원구 상계로 1") ]
    # loans 에 "A" 미지정 → StubService 기본이 :unknown(일시 오류 시뮬레이션).
    stub = StubService.new(holdings: holdings)
    cache = memory_cache
    availability = Library::NearbyAvailability.new(book: sample_book, school: sample_school, service: stub, cache: cache)

    availability.call
    availability.call

    assert_equal 2, stub.loan_calls, ":unknown 은 캐시하지 않아 다음 조회에서 재시도한다(회복 억제 방지)"
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
    result = availability.call

    assert_equal :ok, result.state
    assert_equal fifteen_min_ago, result.as_of, "as_of 는 캐시된 fetched_at(15분 전)이라야 한다"
    assert_equal 0, stub.loan_calls, "대출여부는 캐시 히트라 bookExist 를 호출하지 않는다"
  end
end
