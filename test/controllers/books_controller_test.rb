require "test_helper"

# remote_search 엔드포인트(WS-BE, §Step2) 회귀:
#   - GET /books/remote_search = 네이버 결과 반환 + 서버가 정규화 메타를 book_meta 캐시에 적재.
#   - 무키/실패 시 [](autocomplete/search 와 달리 로컬 폴백 없음). 인가 게이트(로그인) 확인.
# test_helper 가 외부 키를 공란 강제 → 스텁 커넥션을 주입하지 않은 경로는 무키([]).
class BooksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "원격검색학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @student = User.create!(school: @school, classroom: @classroom, name: "원격검색학생", password: "password")
  end

  test "remote_search requires login" do
    get remote_search_books_path, params: { q: "무엇" }
    assert_response :redirect
  end

  test "remote_search returns [] with no keys and no local fallback" do
    # 무키 환경: 로컬에 제목 일치 도서가 있어도 remote_search 는 네이버 전용이라 [] 를 준다
    # (타이핑 autocomplete 와 분리 — 로컬 폴백 없음).
    Book.create!(title: "로컬 어린왕자", author: "생텍쥐페리", category: :recommended)
    login_as(@student)

    get remote_search_books_path, params: { q: "어린" }, as: :json

    assert_response :success
    assert_equal [], response.parsed_body, "remote_search 는 로컬 폴백 없이 무키 시 [] 다"
  end

  test "remote_search returns naver results and caches the server meta on success" do
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.get("/v1/search/book.json") do
        [ 200, {}, {
          "items" => [ {
            "title" => "원격성공책", "author" => "저자", "publisher" => "출판",
            "image" => "http://img/ok", "isbn" => "9783030303030", "description" => "설명"
          } ]
        }.to_json ]
      end
    end
    connection = Faraday.new { |faraday| faraday.adapter :test, stubs }
    keyed = Books::SearchService.new(naver_id: "N", naver_secret: "S", naver_connection: connection)

    login_as(@student)
    # test 환경 cache 는 null_store 라 캐시 적재를 관측할 수 없으므로 memory store 로 교체하고,
    # 컨트롤러가 내부에서 세우는 SearchService.new 를 스텁 커넥션 주입본으로 교체한다
    # (Minitest 6 은 minitest/mock 없음 — 싱글턴 메서드 교체·복원, ocr_test.rb 관례).
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    original_new = Books::SearchService.method(:new)
    Books::SearchService.define_singleton_method(:new) { |*| keyed }
    begin
      get remote_search_books_path, params: { q: "원격" }, as: :json

      assert_response :success
      body = response.parsed_body
      assert_equal 1, body.size
      assert_equal "원격성공책", body.first["title"]
      assert Rails.cache.read("book_meta:9783030303030"), "성공 시 서버 메타가 book_meta 캐시에 적재돼야 한다"
    ensure
      Books::SearchService.define_singleton_method(:new, original_new)
      Rails.cache = original_cache
    end
  end
end
