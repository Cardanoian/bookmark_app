require "test_helper"

# 공용 도서 자동완성 계약(WS-A) 회귀:
#   - GET /books/autocomplete = 로컬 카탈로그(비-searched)만 + id 포함, 외부 호출 0.
#   - GET /books/search = 로컬 폴백 매치에도 id 를 실어 준다(도서 연결용).
# 외부 키는 test_helper 가 공란 강제 → 두 경로 모두 로컬(DB)만 탄다(네이버 무의존).
class BooksAutocompleteTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "자동완성학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @student = User.create!(school: @school, classroom: @classroom, name: "자동완성학생", password: "password")

    @recommended = Book.create!(title: "권장 어린왕자", author: "생텍쥐페리",
                                cover_url: "http://img/prince", category: :recommended)
    @by_author = Book.create!(title: "무제", author: "홍길동", category: :classic)
    @searched = Book.create!(title: "검색캐시 어린왕자", author: "익명", category: :searched)
  end

  test "autocomplete requires login" do
    get autocomplete_books_path, params: { q: "어린" }
    assert_response :redirect
  end

  test "autocomplete returns non-searched local books with id and excludes searched" do
    login_as(@student)
    get autocomplete_books_path, params: { q: "어린" }, as: :json

    assert_response :success
    titles = response.parsed_body.map { |item| item["title"] }
    assert_includes titles, "권장 어린왕자"
    assert_not_includes titles, "검색캐시 어린왕자", "searched 캐시는 카탈로그 자동완성에서 제외돼야 한다"

    item = response.parsed_body.find { |row| row["title"] == "권장 어린왕자" }
    assert_equal @recommended.id, item["id"]
    assert_equal "생텍쥐페리", item["author"]
    assert_equal "http://img/prince", item["cover_url"]
    assert_equal %w[id title author cover_url].sort, item.keys.sort
  end

  test "autocomplete matches by author too" do
    login_as(@student)
    get autocomplete_books_path, params: { q: "홍길" }, as: :json

    assert_response :success
    ids = response.parsed_body.map { |item| item["id"] }
    assert_includes ids, @by_author.id, "저자명 부분 일치도 자동완성에 잡혀야 한다"
  end

  test "autocomplete returns empty array for a blank query" do
    login_as(@student)
    get autocomplete_books_path, params: { q: "  " }, as: :json

    assert_response :success
    assert_equal [], response.parsed_body
  end

  test "search local fallback includes the local book id" do
    login_as(@student)
    get search_books_path, params: { q: "권장 어린왕자" }, as: :json

    assert_response :success
    match = response.parsed_body.find { |row| row["title"] == "권장 어린왕자" }
    assert match, "로컬 폴백이 제목 일치 도서를 반환해야 한다"
    assert_equal @recommended.id, match["id"], "search 응답도 로컬 Book PK(id)를 포함해야 한다"
  end
end
