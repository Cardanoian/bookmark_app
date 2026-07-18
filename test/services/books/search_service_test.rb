require "test_helper"

class Books::SearchServiceTest < ActiveSupport::TestCase
  # 스텁 Faraday 연결(네트워크 차단).
  def stub_connection(&block)
    stubs = Faraday::Adapter::Test::Stubs.new(&block)
    Faraday.new { |faraday| faraday.adapter :test, stubs }
  end

  test "available? is false when the naver keys are blank (placeholder credentials)" do
    assert_not Books::SearchService.new(naver_id: "", naver_secret: "").available?
  end

  test "available? is false when only one naver key is present" do
    assert_not Books::SearchService.new(naver_id: "N", naver_secret: "").available?
    assert_not Books::SearchService.new(naver_id: "", naver_secret: "S").available?
  end

  test "available? is true when both naver keys are present" do
    assert Books::SearchService.new(naver_id: "N", naver_secret: "S").available?
  end

  test "naver success normalizes results and caches them as searched books" do
    connection = stub_connection do |stub|
      stub.get("/v1/search/book.json") do
        [ 200, {}, {
          "items" => [ {
            "title" => "네이버책", "author" => "박작가^김작가", "publisher" => "네이버출판",
            "image" => "http://img/naver", "isbn" => "2222222222 9782222222224", "description" => "네이버 설명"
          } ]
        }.to_json ]
      end
    end
    service = Books::SearchService.new(naver_id: "N", naver_secret: "S", naver_connection: connection)

    results = service.call("네이버")

    assert_equal 1, results.size
    assert_equal "네이버책", results.first[:title]
    assert_equal "박작가, 김작가", results.first[:author]
    assert_equal "9782222222224", results.first[:isbn], "공백 구분 ISBN 은 긴 쪽(ISBN13)을 고른다"

    cached = Book.searched.find_by(isbn: "9782222222224")
    assert cached, "네이버 결과는 searched 도서로 캐시돼야 한다"
    assert_equal "네이버책", cached.title
  end

  test "falls back to local cache when naver request fails" do
    Book.create!(title: "로컬 어린 왕자", author: "생텍쥐페리", category: :recommended)
    naver = stub_connection { |stub| stub.get("/v1/search/book.json") { [ 500, {}, "server error" ] } }
    service = Books::SearchService.new(naver_id: "N", naver_secret: "S", naver_connection: naver)

    results = service.call("어린")

    assert_equal 1, results.size
    assert_equal "로컬 어린 왕자", results.first[:title]
  end

  test "falls back to local cache when keys are blank (no network)" do
    Book.create!(title: "로컬 어린 왕자", author: "생텍쥐페리", category: :recommended)
    service = Books::SearchService.new(naver_id: "", naver_secret: "")

    results = service.call("어린")

    assert_equal 1, results.size
    assert_equal "로컬 어린 왕자", results.first[:title]
  end

  test "returns an empty array for a blank query" do
    assert_equal [], Books::SearchService.new(naver_id: "N", naver_secret: "S").call("")
  end

  test "skips items with a blank title so a malformed item can't pollute results" do
    connection = stub_connection do |stub|
      stub.get("/v1/search/book.json") do
        [ 200, {}, {
          "items" => [
            { "title" => "", "author" => "익명", "isbn" => "9783333333335" },
            { "title" => "정상책", "author" => "정상작가", "isbn" => "9784444444446" }
          ]
        }.to_json ]
      end
    end
    service = Books::SearchService.new(naver_id: "N", naver_secret: "S", naver_connection: connection)

    results = service.call("검색어")

    assert_equal 1, results.size, "제목이 빈 항목은 건너뛰어야 한다"
    assert_equal "정상책", results.first[:title]
  end

  test "skips non-Hash items in the naver response without crashing" do
    connection = stub_connection do |stub|
      stub.get("/v1/search/book.json") do
        [ 200, {}, { "items" => [ "malformed-string-item", { "title" => "정상책" } ] }.to_json ]
      end
    end
    service = Books::SearchService.new(naver_id: "N", naver_secret: "S", naver_connection: connection)

    results = service.call("검색어")

    assert_equal 1, results.size, "Hash 가 아닌 항목은 건너뛰어야 한다"
    assert_equal "정상책", results.first[:title]
  end

  # 동기 웹요청 경로(도서 검색)의 스레드 고갈을 막기 위해 실 Faraday 연결에 타임아웃을 설정한다(§0.4).
  test "real naver connection is configured with http timeouts (open 3s / read 8s)" do
    connection = Books::SearchService.new(naver_id: "N", naver_secret: "S").send(:naver_connection)
    assert_equal 3, connection.options.open_timeout
    assert_equal 8, connection.options.timeout
  end

  # --- #remote_search (검색 버튼 전용, 메타 캐시 적재) ---------------------------------

  # test 환경 cache 는 null_store 라 write/read 가 no-op. 캐시-우선 경로(#remote_search /
  # #register)를 검증하려면 실제 저장되는 memory store 로 잠시 교체한다.
  def with_memory_cache
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    yield
  ensure
    Rails.cache = original
  end

  test "#remote_search caches naver meta by isbn and never writes to the books table" do
    connection = stub_connection do |stub|
      stub.get("/v1/search/book.json") do
        [ 200, {}, {
          "items" => [
            { "title" => "원격책", "author" => "저자", "publisher" => "출판",
              "image" => "http://img/remote", "isbn" => "9785555555557", "description" => "설명" },
            { "title" => "무isbn책", "author" => "저자2", "isbn" => "" }
          ]
        }.to_json ]
      end
    end
    service = Books::SearchService.new(naver_id: "N", naver_secret: "S", naver_connection: connection)

    with_memory_cache do
      results = nil
      assert_no_difference "Book.count", "원격 검색은 books 테이블에 쓰지 않는다(캐시만)" do
        results = service.remote_search("원격")
      end
      assert_equal 2, results.size

      cached = Rails.cache.read("book_meta:9785555555557")
      assert cached, "isbn 있는 결과는 book_meta 캐시에 적재돼야 한다"
      assert_equal "원격책", cached[:title]
      assert_nil Rails.cache.read("book_meta:"), "isbn 공란 결과는 캐시하지 않는다"
    end
  end

  test "#remote_search returns [] with no keys (no local fallback) and caches nothing" do
    Book.create!(title: "로컬 어린 왕자", author: "생텍쥐페리", category: :recommended)
    service = Books::SearchService.new(naver_id: "", naver_secret: "")

    with_memory_cache do
      assert_equal [], service.remote_search("어린"), "무키 시 remote_search 는 로컬 폴백 없이 [] 다"
    end
  end

  # --- #register (제출 시 등록, 캐시-우선 3단, nil degrade) -----------------------------

  test "#register uses cached server meta (not client payload) with no naver call" do
    # 무키 서비스 → #query 는 네트워크 0. 등록이 오로지 캐시 메타에서만 나옴을 보장한다.
    service = Books::SearchService.new(naver_id: "", naver_secret: "")

    with_memory_cache do
      Rails.cache.write("book_meta:9786666666668", {
        id: nil, title: "서버메타 제목", author: "서버저자", publisher: "출판",
        thumbnail: "http://img/x", isbn: "9786666666668", description: "설명"
      })

      book = nil
      assert_difference "Book.count", 1 do
        book = service.register("9786666666668")
      end
      assert_equal "9786666666668", book.isbn
      assert_equal "서버메타 제목", book.title, "저장된 title 은 캐시(서버 메타)에서 온다 — 클라 payload 아님"
      assert book.searched?, "네이버 신규 등록은 category: searched"
    end
  end

  test "#register returns the existing book when the isbn is already in the catalog" do
    existing = Book.create!(title: "선존책", isbn: "9787777777779", category: :recommended)
    service = Books::SearchService.new(naver_id: "", naver_secret: "")

    with_memory_cache do
      assert_no_difference "Book.count" do
        assert_equal existing.id, service.register("9787777777779").id
      end
    end
  end

  test "#register falls back to #query when the cache misses and upserts the matching isbn" do
    connection = stub_connection do |stub|
      stub.get("/v1/search/book.json") do
        [ 200, {}, {
          "items" => [ {
            "title" => "폴백책", "author" => "폴백저자", "publisher" => "출판",
            "image" => "http://img/f", "isbn" => "9788888888880", "description" => "설명"
          } ]
        }.to_json ]
      end
    end
    service = Books::SearchService.new(naver_id: "N", naver_secret: "S", naver_connection: connection)

    with_memory_cache do # 캐시 비어 있음 → 미스 → #query 폴백
      book = nil
      assert_difference "Book.count", 1 do
        book = service.register("9788888888880")
      end
      assert_equal "폴백책", book.title
      assert book.searched?
    end
  end

  test "#register returns nil when the query result isbn does not match the request" do
    connection = stub_connection do |stub|
      stub.get("/v1/search/book.json") do
        [ 200, {}, { "items" => [ { "title" => "다른책", "isbn" => "9789999999991" } ] }.to_json ]
      end
    end
    service = Books::SearchService.new(naver_id: "N", naver_secret: "S", naver_connection: connection)

    with_memory_cache do
      assert_no_difference "Book.count" do
        assert_nil service.register("9781010101017"), "요청 isbn 과 불일치하면 등록하지 않는다"
      end
    end
  end

  test "#register returns nil with no keys and an empty cache (graceful degrade, no raise)" do
    service = Books::SearchService.new(naver_id: "", naver_secret: "")

    with_memory_cache do
      assert_no_difference "Book.count" do
        assert_nil service.register("9781212121219")
      end
    end
  end

  test "#register returns nil for a blank isbn" do
    assert_nil Books::SearchService.new(naver_id: "", naver_secret: "").register("")
  end

  # 진짜 동시성 레이스(uniqueness 검증 SELECT 후·INSERT 전에 동일 isbn 이 커밋되는 창)를
  # 결정적으로 재현한다: find_or_initialize_by 가 신규 레코드를 돌려주고 그 레코드의 save 가
  # DB 유니크 위반(RecordNotUnique)을 일으키게 스텁 → rescue 가 선존 행을 재조회해 500 없이
  # 단일 행으로 수렴함을 검증한다(소프트 검증이 못 잡는 레이스를 DB 인덱스+rescue 가 백스톱).
  # Minitest 6 은 minitest/mock 없음 — 싱글턴 메서드를 교체·복원한다(ocr_test.rb 관례).
  test "#upsert rescues RecordNotUnique and converges to the existing row" do
    existing = Book.create!(title: "레이스책", isbn: "9782020202022", category: :searched)
    service = Books::SearchService.new(naver_id: "", naver_secret: "")
    attrs = {
      id: nil, title: "레이스책", author: "저자", publisher: "출판",
      thumbnail: "http://img", isbn: "9782020202022", description: "설명"
    }

    racing = Book.new(isbn: "9782020202022", title: "레이스책")
    racing.define_singleton_method(:save) do |*|
      raise ActiveRecord::RecordNotUnique, "duplicate isbn (simulated INSERT race)"
    end
    original = Book.method(:find_or_initialize_by)
    Book.define_singleton_method(:find_or_initialize_by) { |*| racing }
    begin
      result = nil
      assert_no_difference "Book.count" do
        result = service.send(:upsert, attrs)
      end
      assert_equal existing.id, result.id, "레이스 후 선존 행으로 수렴해야 한다"
    ensure
      Book.define_singleton_method(:find_or_initialize_by, original)
    end
  end
end
