require "test_helper"

class BooksCatalogTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "도서통합초")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @student = User.create!(school: @school, classroom: @classroom, name: "도서학생", password: "password")
    @recommended = Book.create!(title: "권장 마당을 나온 암탉", author: "황선미", category: :recommended)
    @classic = Book.create!(title: "고전 어린 왕자", author: "생텍쥐페리", category: :classic)
  end

  test "catalog index lists every book" do
    login_as @student
    get books_path
    assert_response :success
    assert_match "마당을 나온 암탉", response.body
    assert_match "어린 왕자", response.body
  end

  test "catalog index filters by category" do
    login_as @student
    get books_path(category: "classic")
    assert_response :success
    assert_match "어린 왕자", response.body
    assert_no_match(/마당을 나온 암탉/, response.body)
  end

  test "search returns local matches as JSON when offline (no api keys)" do
    login_as @student
    get search_books_path(q: "어린")
    assert_response :success
    results = JSON.parse(response.body)
    assert_equal 1, results.size
    assert_equal "고전 어린 왕자", results.first["title"]
  end

  test "search requires login" do
    get search_books_path(q: "어린")
    assert_redirected_to new_session_path
  end

  # #2: 검색 upsert 캐시(category: searched)는 카탈로그 목록에 노출되지 않는다(무한 증가 방어).
  test "searched-category rows are excluded from the catalog index" do
    Book.create!(title: "검색캐시책", author: "네이버", category: :searched, isbn: "9788900000001")
    login_as @student

    get books_path
    assert_response :success
    assert_no_match(/검색캐시책/, response.body)
    assert_match "마당을 나온 암탉", response.body # 일반 카탈로그는 그대로 노출
  end

  # #2: 카탈로그 index 는 페이지네이션되어 무제한 로드되지 않는다.
  test "catalog index paginates into PER_PAGE slices with a next link" do
    (BooksController::PER_PAGE + 3).times do |i|
      Book.create!(title: "페이지책#{format('%03d', i)}", category: :recommended)
    end
    login_as @student

    get books_path
    assert_response :success
    assert_match "다음", response.body, "다음 페이지 링크가 있어야 한다"

    get books_path(page: 2)
    assert_response :success
    assert_match "이전", response.body
  end

  def login_as(user)
    post session_path, params: {
      school_id: user.school_id, classroom_id: user.classroom_id,
      name: user.name, password: "password"
    }
  end
end
