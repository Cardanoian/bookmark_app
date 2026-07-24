require "test_helper"

# books:enrich 코어. ISBN 정확 일치 네이버 결과로 표지·출판사를 제자리 보강하고,
# 별도 :searched 행을 만들지 않으며 무키 시 no-op 임을 검증한다.
class Books::CatalogEnricherTest < ActiveSupport::TestCase
  def stub_service(&block)
    stubs = Faraday::Adapter::Test::Stubs.new(&block)
    connection = Faraday.new { |faraday| faraday.adapter :test, stubs }
    Books::SearchService.new(naver_id: "N", naver_secret: "S", naver_connection: connection)
  end

  # 정보나루 표지 폴백 스텁(네트워크 차단). 네이버가 반환하지 않는 검색 결과는 [] 로 두고
  # 이 스텁이 srchDtlList 표지를 제공한다.
  def stub_library(&block)
    stubs = Faraday::Adapter::Test::Stubs.new(&block)
    connection = Faraday.new { |faraday| faraday.adapter :test, stubs }
    Library::Data4libraryService.new(api_key: "K", connection: connection)
  end

  # 무키(오프라인) 정보나루. 폴백을 타지 않는 경로에서 실 네트워크를 막기 위해 명시 주입한다.
  def offline_library
    Library::Data4libraryService.new(api_key: "")
  end

  def naver_item(overrides = {})
    {
      "title" => "테스트도서", "author" => "테스트작가", "publisher" => "테스트출판",
      "image" => "http://img/cover", "isbn" => "9791234567896", "description" => "설명"
    }.merge(overrides)
  end

  test "enriches a curated book in place without creating a searched row" do
    book = Book.create!(title: "테스트도서", author: "테스트작가", category: :recommended,
                        grade_band: "초등 5~6", isbn: "9791234567896")
    service = stub_service do |stub|
      stub.get("/v1/search/book.json") { [ 200, {}, { "items" => [ naver_item ] }.to_json ] }
    end

    updated = Books::CatalogEnricher.new(service: service, throttle: 0).enrich_all

    assert_equal 1, updated
    book.reload
    assert_equal "9791234567896", book.isbn
    # 네이버 원본은 http:// 지만 Book#upgrade_cover_url_to_https 콜백이 저장 시 https:// 로 승격한다.
    assert_equal "https://img/cover", book.cover_url
    assert_equal "테스트출판", book.publisher
    assert_equal 0, Book.searched.count, "enrich 는 별도 searched 행을 만들지 않는다"
  end

  test "offline (no key) is a no-op leaving curated fields intact" do
    book = Book.create!(title: "무키도서", author: "저자", category: :recommended, grade_band: "초등 1~2")
    offline = Books::SearchService.new(naver_id: "", naver_secret: "")

    # 정보나루도 무키로 명시 주입해 양쪽 공급원 오프라인 시 no-op 임을 결정적으로 검증한다.
    updated = Books::CatalogEnricher.new(service: offline, library: offline_library, throttle: 0).enrich_all

    assert_equal 0, updated
    book.reload
    assert_nil book.cover_url
    assert_equal 0, Book.searched.count
  end

  test "skips books that already have both isbn and cover" do
    Book.create!(title: "이미보강", author: "저자", category: :recommended, grade_band: "초등 5~6",
                 isbn: "9791111111112", cover_url: "http://img/x")
    service = stub_service do |stub|
      stub.get("/v1/search/book.json") { [ 200, {}, { "items" => [] }.to_json ] }
    end

    updated = Books::CatalogEnricher.new(service: service, throttle: 0).enrich_all

    assert_equal 0, updated
  end

  test "uses an existing ISBN as the query and accepts only the exact ISBN result" do
    book = Book.create!(title: "동명 도서", author: "정확한 저자", category: :recommended,
                        isbn: "979-12-3456-789-6")
    service = stub_service do |stub|
      stub.get("/v1/search/book.json") do |env|
        assert_equal "9791234567896", env.params["query"]
        items = [
          naver_item("title" => "동명 도서", "isbn" => "9790000000001", "image" => "http://img/wrong"),
          naver_item("title" => "다른 표기", "isbn" => "9791234567896", "image" => "http://img/exact")
        ]
        [ 200, {}, { "items" => items }.to_json ]
      end
    end

    updated = Books::CatalogEnricher.new(service: service, throttle: 0).enrich_all

    assert_equal 1, updated
    # 네이버 원본 http:// → 콜백이 https:// 로 승격(혼합 콘텐츠 가드).
    assert_equal "https://img/exact", book.reload.cover_url
    assert_equal "9791234567896", book.isbn, "저장 시 하이픈 없는 ISBN-13으로 정규화한다"
  end

  # --- 정보나루 표지 폴백: 네이버가 색인하지 못한 판본(ISBN 0건)의 cover 보강 ---

  test "falls back to data4library cover when Naver has no exact ISBN match" do
    book = Book.create!(title: "치폴리노의 모험", author: "잔니 로다리", category: :recommended,
                        isbn: "9788949140926")
    service = stub_service do |stub|
      stub.get("/v1/search/book.json") { [ 200, {}, { "items" => [] }.to_json ] } # 네이버 0건
    end
    library = stub_library do |stub|
      stub.get("/api/srchDtlList") do
        [ 200, {}, { "response" => { "detail" => [
          { "book" => { "isbn13" => "9788949140926", "bookImageURL" => "https://img/chipollino.jpg" } }
        ] } }.to_json ]
      end
    end

    updated = Books::CatalogEnricher.new(service: service, library: library, throttle: 0).enrich_all

    assert_equal 1, updated
    assert_equal "https://img/chipollino.jpg", book.reload.cover_url
    assert_equal 0, Book.searched.count, "폴백도 별도 searched 행을 만들지 않는다"
  end

  test "Naver exact match takes precedence over the data4library fallback" do
    book = Book.create!(title: "우선순위", author: "저자", category: :recommended, isbn: "9791234567896")
    service = stub_service do |stub|
      stub.get("/v1/search/book.json") { [ 200, {}, { "items" => [ naver_item ] }.to_json ] }
    end
    # 폴백이 호출되면 실패(등록되지 않은 경로)하도록 빈 스텁을 준다 — 네이버 매치 시 폴백은 없어야 한다.
    library = stub_library { |stub| }

    updated = Books::CatalogEnricher.new(service: service, library: library, throttle: 0).enrich_all

    assert_equal 1, updated
    assert_equal "https://img/cover", book.reload.cover_url, "네이버 표지가 우선 적용된다(콜백 https 승격)"
  end

  test "enriches via data4library even when Naver is unavailable (relaxed gate)" do
    book = Book.create!(title: "네이버무키", author: "저자", category: :recommended, isbn: "9788949140926")
    offline_naver = Books::SearchService.new(naver_id: "", naver_secret: "")
    library = stub_library do |stub|
      stub.get("/api/srchDtlList") do
        [ 200, {}, { "response" => { "detail" => [
          { "book" => { "bookImageURL" => "https://img/x.jpg" } }
        ] } }.to_json ]
      end
    end

    updated = Books::CatalogEnricher.new(service: offline_naver, library: library, throttle: 0).enrich_all

    assert_equal 1, updated
    assert_equal "https://img/x.jpg", book.reload.cover_url
  end

  test "leaves the cover blank when neither Naver nor data4library has the book" do
    book = Book.create!(title: "어디에도없는책", author: "저자", category: :recommended, isbn: "9788949140926")
    service = stub_service do |stub|
      stub.get("/v1/search/book.json") { [ 200, {}, { "items" => [] }.to_json ] }
    end
    library = stub_library do |stub|
      stub.get("/api/srchDtlList") { [ 200, {}, { "response" => { "detail" => [] } }.to_json ] }
    end

    updated = Books::CatalogEnricher.new(service: service, library: library, throttle: 0).enrich_all

    assert_equal 0, updated
    assert_nil book.reload.cover_url
  end
end
