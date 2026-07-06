require "test_helper"

# P6.4 교무관리자 전교 통계: 자기 학교 집계 · 타학교 데이터 배제 · 경계 인가.
class SchoolAdminStatsTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "우리학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @admin = User.create!(school: @school, name: "우리교무", role: :school_admin, password: "password")
    @student = User.create!(school: @school, classroom: @classroom, name: "우리학생", password: "password")
    @book = Book.create!(title: "우리책")
    @report = Report.create!(user: @student, classroom: @classroom, book: @book, book_title: "우리책",
                             body: "본문", rubric: { content: 4, emotion: 4, life: 5, structure: 3, spelling: 4 },
                             avg: 4.0, level: "A", reviewed: true)

    # 타학교(경계 검증용).
    @other_school = School.create!(name: "남의학교")
    @other_classroom = Classroom.create!(school: @other_school, grade: 6, class_no: 3)
    @other_admin = User.create!(school: @other_school, name: "남의교무", role: :school_admin, password: "password")
    @other_student = User.create!(school: @other_school, classroom: @other_classroom, name: "비밀학생", password: "password")
    Report.create!(user: @other_student, classroom: @other_classroom, book_title: "비밀책", body: "본문",
                   rubric: { content: 1, emotion: 1, life: 1, structure: 1, spelling: 1 }, avg: 1.0, level: "C", reviewed: true)
  end

  test "renders own-school aggregates" do
    login_as @admin
    get school_admin_stats_path
    assert_response :success
    assert_match "우리학교", response.body
  end

  test "does not leak another school's data" do
    login_as @admin
    get school_admin_stats_path
    assert_response :success
    assert_no_match "비밀학생", response.body
    assert_no_match "비밀책", response.body
  end

  test "a teacher is forbidden from school_admin stats" do
    teacher = User.create!(school: @school, classroom: @classroom, name: "교사X", role: :teacher, password: "password")
    login_as teacher
    get school_admin_stats_path
    assert_response :forbidden
  end

  test "a student is forbidden" do
    login_as @student
    get school_admin_stats_path
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
