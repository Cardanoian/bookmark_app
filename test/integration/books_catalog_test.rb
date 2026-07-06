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

  def login_as(user)
    post session_path, params: {
      school_id: user.school_id, classroom_id: user.classroom_id,
      name: user.name, password: "password"
    }
  end
end
