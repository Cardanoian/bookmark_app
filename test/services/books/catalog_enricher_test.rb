require "test_helper"

# books:enrich 코어(계획 §3.2·§5). 큐레이션 도서를 네이버 결과로 제자리 보강하되 별도 :searched
# 행을 만들지 않고, 선존 동일 isbn searched 행은 정리하며, 무키 시 no-op 임을 검증한다.
class Books::CatalogEnricherTest < ActiveSupport::TestCase
  def stub_service(&block)
    stubs = Faraday::Adapter::Test::Stubs.new(&block)
    connection = Faraday.new { |faraday| faraday.adapter :test, stubs }
    Books::SearchService.new(naver_id: "N", naver_secret: "S", naver_connection: connection)
  end

  def naver_item(overrides = {})
    {
      "title" => "테스트도서", "author" => "테스트작가", "publisher" => "테스트출판",
      "image" => "http://img/cover", "isbn" => "9791234567890", "description" => "설명"
    }.merge(overrides)
  end

  test "enriches a curated book in place without creating a searched row" do
    book = Book.create!(title: "테스트도서", author: "테스트작가", category: :recommended, grade_band: "초등 5~6")
    service = stub_service do |stub|
      stub.get("/v1/search/book.json") { [ 200, {}, { "items" => [ naver_item ] }.to_json ] }
    end

    updated = Books::CatalogEnricher.new(service: service, throttle: 0).enrich_all

    assert_equal 1, updated
    book.reload
    assert_equal "9791234567890", book.isbn
    assert_equal "http://img/cover", book.cover_url
    assert_equal "테스트출판", book.publisher
    assert_equal 0, Book.searched.count, "enrich 는 별도 searched 행을 만들지 않는다"
  end

  test "reconciles a pre-existing searched row and re-points its report links to the curated book" do
    curated = Book.create!(title: "정본도서", author: "저자", category: :recommended, grade_band: "초등 3~4")
    searched = Book.create!(title: "정본도서(검색캐시)", isbn: "9790000000001", category: :searched)

    # 학생이 검색캐시(:searched) 행으로 독후감을 이미 썼다고 가정 — 보강이 이 링크를 끊으면 안 된다
    # (reports.book_id on_delete: nullify). 삭제 전에 정본 도서로 이관되어 링크가 보존돼야 한다(§8).
    school = School.create!(name: "보강학교")
    classroom = Classroom.create!(school: school, grade: 3, class_no: 1)
    student = User.create!(school: school, classroom: classroom, name: "보강학생", password: "password")
    report = Report.create!(user: student, classroom: classroom, book: searched, book_title: "정본도서")

    service = stub_service do |stub|
      stub.get("/v1/search/book.json") do
        [ 200, {}, { "items" => [ naver_item("title" => "정본도서", "author" => "저자", "isbn" => "9790000000001") ] }.to_json ]
      end
    end

    Books::CatalogEnricher.new(service: service, throttle: 0).enrich_all

    curated.reload
    assert_equal "9790000000001", curated.isbn
    assert_not Book.exists?(searched.id), "동일 isbn 의 선존 searched 행은 정리된다"
    assert_equal 1, Book.where(isbn: "9790000000001").count, "동일 isbn 은 단일 행으로 수렴한다"

    report.reload
    assert_equal curated.id, report.book_id,
                 "searched 행 삭제 전 독후감 링크를 정본(큐레이션) 도서로 이관해 보존한다(nullify 되지 않음)"
  end

  test "offline (no key) is a no-op leaving curated fields intact" do
    book = Book.create!(title: "무키도서", author: "저자", category: :recommended, grade_band: "초등 1~2")
    offline = Books::SearchService.new(naver_id: "", naver_secret: "")

    updated = Books::CatalogEnricher.new(service: offline, throttle: 0).enrich_all

    assert_equal 0, updated
    book.reload
    assert_nil book.isbn
    assert_equal 0, Book.searched.count
  end

  test "skips books that already have both isbn and cover" do
    Book.create!(title: "이미보강", author: "저자", category: :recommended, grade_band: "초등 5~6",
                 isbn: "9791111111111", cover_url: "http://img/x")
    service = stub_service do |stub|
      stub.get("/v1/search/book.json") { [ 200, {}, { "items" => [] }.to_json ] }
    end

    updated = Books::CatalogEnricher.new(service: service, throttle: 0).enrich_all

    assert_equal 0, updated
  end
end
