require "test_helper"

# "이 책은 어때요?" 발견 학년군 인기도서 풀 캐시 — 무쓰기 카탈로그 매칭.
# 주입 MemoryStore + 스텁 서비스(무네트워크)로 pool_book_ids(캐시히트/미스/스탬피드 가드)와
# warm(ISBN 정규화·카탈로그 교집합·인기순·MIN_POOL 임계·멱등)을 검증한다.
class Library::PopularDiscoveryTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  # 네트워크 없는 스텁 서비스. popular_loans 는 loans 를 그대로 돌려주고 호출 인자를 캡처한다.
  class StubService
    attr_reader :popular_loans_calls, :captured_args

    def initialize(available: true, loans: [])
      @available = available
      @loans = loans
      @popular_loans_calls = 0
    end

    def available? = @available

    def popular_loans(from: nil, to: nil, page_size: 10, age: nil)
      @popular_loans_calls += 1
      @captured_args = { from: from, to: to, page_size: page_size, age: age }
      @loans
    end
  end

  # test_helper 의 TestBookIsbn 과 동형인 결정적 유효 ISBN-13 생성기(체크디지트 포함).
  def isbn_for(seq)
    base = "978#{seq.to_s.rjust(9, "0")}"
    "#{base}#{Books::Isbn.isbn13_check_digit(base)}"
  end

  def loan(isbn, title: "인기책", count: 1)
    { book_title: title, isbn: isbn, count: count }
  end

  def memory_cache = ActiveSupport::Cache::MemoryStore.new

  def build(cache:, service:, now: -> { Time.current })
    Library::PopularDiscovery.new(cache: cache, service: service, now: now)
  end

  # --- pool_book_ids: 캐시 히트 ---

  test "pool_book_ids returns the cached pool without calling the service (cache hit)" do
    cache = memory_cache
    cache.write("discovery_popular:v1:g56", [ 10, 20, 30 ])
    service = StubService.new
    discovery = build(cache: cache, service: service)

    result = nil
    assert_no_enqueued_jobs do
      result = discovery.pool_book_ids(:g56)
    end

    assert_equal [ 10, 20, 30 ], result
    assert_equal 0, service.popular_loans_calls
  end

  # --- pool_book_ids: 미스 + 무키 ---

  test "pool_book_ids returns [] and does not enqueue a job when the service is unavailable (no key)" do
    cache = memory_cache
    discovery = build(cache: cache, service: StubService.new(available: false))

    result = nil
    assert_no_enqueued_jobs do
      result = discovery.pool_book_ids(:g56)
    end

    assert_equal [], result
    assert_not cache.exist?("discovery_warming:v1:g56"), "무키면 스탬피드 마커도 기록하지 않는다(무한 enqueue 방지)"
  end

  # --- pool_book_ids: 미스 + available → 워밍 큐잉 + 스탬피드 가드 ---

  test "pool_book_ids returns [] and enqueues the warm job on a cache miss (available service)" do
    cache = memory_cache
    discovery = build(cache: cache, service: StubService.new(available: true))

    result = nil
    assert_enqueued_with(job: Library::PopularDiscoveryWarmJob, args: [ "g56" ]) do
      result = discovery.pool_book_ids(:g56)
    end

    assert_equal [], result
    assert cache.exist?("discovery_warming:v1:g56"), "원자 마커를 획득해야 한다"
  end

  test "pool_book_ids does not enqueue a second warm job while the warming marker is held (stampede guard)" do
    cache = memory_cache
    discovery = build(cache: cache, service: StubService.new(available: true))

    discovery.pool_book_ids(:g56)
    assert_enqueued_jobs 1

    discovery.pool_book_ids(:g56) # 마커가 아직 살아있음 → 재큐잉 스킵

    assert_enqueued_jobs 1 # 진행 중 마커가 있으면 반 동시접속 콜드캐시도 1콜/WARMING_TTL 로 상한된다
  end

  # --- warm: ISBN 정규화 + 카탈로그(non-searched) 교집합 + 인기순 캐시 ---

  test "warm caches only matched non-searched book ids in popularity order, excluding searched/invalid/out-of-catalog isbns" do
    matched_isbns = (1..12).map { |i| isbn_for(i) }
    matched_books = matched_isbns.each_with_index.map do |isbn, i|
      Book.create!(title: "인기책#{i}", author: "작가", isbn: isbn, category: i.even? ? :recommended : :classic)
    end
    searched_isbn = isbn_for(100)
    Book.create!(title: "검색캐시책", author: "작가", isbn: searched_isbn, category: :searched)
    outside_isbn = isbn_for(200) # 카탈로그에 없는 도서(교집합 밖)
    invalid_isbn = "not-an-isbn"

    # 인기순(=loans 순서) 사이에 searched·무효·카탈로그밖 항목을 섞어, 매칭분만 상대 순서를 보존한 채
    # 남는지 검증한다.
    loans = [
      loan(matched_isbns[0]), loan(searched_isbn), loan(matched_isbns[1]), loan(invalid_isbn),
      loan(matched_isbns[2]), loan(outside_isbn), loan(matched_isbns[3]), loan(matched_isbns[4]),
      loan(matched_isbns[5]), loan(matched_isbns[6]), loan(matched_isbns[7]), loan(matched_isbns[8]),
      loan(matched_isbns[9]), loan(matched_isbns[10]), loan(matched_isbns[11])
    ]
    cache = memory_cache
    discovery = build(cache: cache, service: StubService.new(loans: loans))

    discovery.warm(:g56)

    expected_ids = matched_books.map(&:id)
    assert_equal expected_ids, cache.read("discovery_popular:v1:g56")
  end

  test "warm does not cache the pool when matches fall below MIN_POOL (keeps fallback)" do
    matched = (1..5).map { |i| Book.create!(title: "적음#{i}", author: "작가", isbn: isbn_for(i), category: :recommended) }
    loans = matched.map { |book| loan(book.isbn) }
    cache = memory_cache
    discovery = build(cache: cache, service: StubService.new(loans: loans))

    assert_operator matched.size, :<, Library::PopularDiscovery::MIN_POOL

    discovery.warm(:g56)

    assert_nil cache.read("discovery_popular:v1:g56")
  end

  test "warm is idempotent when the pool already exists (no service call)" do
    cache = memory_cache
    cache.write("discovery_popular:v1:g56", [ 1, 2, 3 ])
    service = StubService.new
    discovery = build(cache: cache, service: service)

    discovery.warm(:g56)

    assert_equal 0, service.popular_loans_calls
    assert_equal [ 1, 2, 3 ], cache.read("discovery_popular:v1:g56")
  end

  test "warm is a no-op for an unmapped band (age blank)" do
    cache = memory_cache
    service = StubService.new
    discovery = build(cache: cache, service: service)

    discovery.warm(:unmapped_band)

    assert_equal 0, service.popular_loans_calls
    assert_nil cache.read("discovery_popular:v1:unmapped_band")
  end

  test "warm passes the band's age code, the previous month's period, and POOL_LIMIT as page_size" do
    fixed = Time.zone.local(2026, 7, 23, 10, 0, 0)
    cache = memory_cache
    service = StubService.new(loans: [])
    discovery = build(cache: cache, service: service, now: -> { fixed })

    discovery.warm(:g56)

    assert_equal "a12", service.captured_args[:age]
    assert_equal "2026-06-01", service.captured_args[:from]
    assert_equal "2026-06-30", service.captured_args[:to]
    assert_equal Library::PopularDiscovery::POOL_LIMIT, service.captured_args[:page_size]
  end

  test "warm accepts band as a string (perform_later argument round-trip)" do
    matched = (1..12).map { |i| Book.create!(title: "문자열밴드#{i}", author: "작가", isbn: isbn_for(i), category: :recommended) }
    loans = matched.map { |book| loan(book.isbn) }
    cache = memory_cache
    discovery = build(cache: cache, service: StubService.new(loans: loans))

    discovery.warm("g12")

    assert_equal matched.map(&:id), cache.read("discovery_popular:v1:g12")
  end
end
