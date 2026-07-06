require "test_helper"

# P6.4 NEIS 생기부 자동요약: 학생 선택 → 오프라인 템플릿 요약 · 학교 경계.
class SchoolAdminNeisTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "생기부학교")
    @classroom = Classroom.create!(school: @school, grade: 6, class_no: 1)
    @admin = User.create!(school: @school, name: "생기부교무", role: :school_admin, password: "password")
    @student = User.create!(school: @school, classroom: @classroom, name: "성실학생", password: "password")
    @book = Book.create!(title: "마당을 나온 암탉")
    Report.create!(user: @student, classroom: @classroom, book: @book, book_title: @book.title, body: "본문",
                   rubric: { content: 5, emotion: 4, life: 4, structure: 3, spelling: 4 }, avg: 4.0, level: "A", reviewed: true)
  end

  test "index lists the school's students" do
    login_as @admin
    get school_admin_neis_path
    assert_response :success
    assert_match "성실학생", response.body
  end

  test "generates a 생기부 summary offline for a selected student (no api key)" do
    login_as @admin
    get school_admin_neis_path, params: { student_id: @student.id }
    assert_response :success
    assert_match "성실학생", response.body
    assert_match "독후감", response.body
    assert_match "마당을 나온 암탉", response.body
  end

  test "cannot summarize a student from another school (scope)" do
    other_school = School.create!(name: "타생기부학교")
    other_classroom = Classroom.create!(school: other_school, grade: 5, class_no: 2)
    outsider = User.create!(school: other_school, classroom: other_classroom, name: "외부학생", password: "password")

    login_as @admin
    get school_admin_neis_path, params: { student_id: outsider.id }
    assert_response :success
    assert_no_match "외부학생", response.body
  end

  test "a librarian is forbidden from NEIS summaries" do
    librarian = User.create!(school: @school, name: "생기부사서", role: :librarian, password: "password")
    login_as librarian
    get school_admin_neis_path
    assert_response :forbidden
  end

  private

  def login_as(user)
    post session_path, params: {
      school_id: user.school_id, classroom_id: user.classroom_id,
      name: user.name, password: "password"
    }
  end
end
