require "test_helper"

# P6.1 교사 대시보드: 5축 평균·방사형 SVG·A비율·검토대기·약점 인사이트.
class TeacherDashboardTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "대시보드학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @teacher = User.create!(school: @school, classroom: @classroom, name: "대시담임", role: :teacher, password: "password", approved: true)
    @classroom.update!(teacher: @teacher)
    @student = User.create!(school: @school, classroom: @classroom, name: "대시학생", password: "password")

    rubric = { "content" => 5, "emotion" => 4, "life" => 4, "structure" => 3, "spelling" => 2 }
    @a1 = Report.create!(user: @student, classroom: @classroom, book_title: "책1", rubric: rubric, avg: 4.2, level: "A", ai_status: :done, reviewed: true)
    @a2 = Report.create!(user: @student, classroom: @classroom, book_title: "책2", rubric: rubric, avg: 4.1, level: "A", ai_status: :done, reviewed: true)
    @b1 = Report.create!(user: @student, classroom: @classroom, book_title: "책3", rubric: rubric, avg: 3.0, level: "B", ai_status: :done, reviewed: false)
  end

  test "dashboard renders the radar svg and 5축 averages" do
    login_as @teacher
    get teacher_dashboard_path

    assert_response :success
    assert_match "<svg", response.body
    assert_match "<polygon", response.body
    assert_match ReadingDomain::AXIS_LABELS[:content], response.body
  end

  test "dashboard reports correct A ratio and pending count" do
    login_as @teacher
    get teacher_dashboard_path

    assert_response :success
    assert_match "67%", response.body # A 2 of 3 scored
    assert_match "검토 대기", response.body
  end

  test "dashboard surfaces the weakest axis insight" do
    login_as @teacher
    get teacher_dashboard_path

    assert_response :success
    # 가장 낮은 축은 맞춤법(2점) → 성취기준 코드 노출
    assert_match ReadingDomain::ACHIEVEMENT_STANDARDS[:spelling], response.body
  end

  test "dashboard improvement average matches the SQL aggregate" do
    # improvement 기록이 있는 리포트 2개 → 평균 향상도 = (0.5 + 1.5) / 2 = 1.0
    Report.create!(user: @student, classroom: @classroom, book_title: "고쳐1", improvement: 0.5, avg: 3.0, level: "B", ai_status: :done)
    Report.create!(user: @student, classroom: @classroom, book_title: "고쳐2", improvement: 1.5, avg: 3.0, level: "B", ai_status: :done)
    login_as @teacher

    get teacher_dashboard_path
    assert_response :success
    assert_match "1.0점", response.body
  end

  test "a student is forbidden from the teacher dashboard" do
    login_as @student
    get teacher_dashboard_path
    assert_response :forbidden
  end

  test "a librarian is forbidden from the teacher dashboard" do
    librarian = User.create!(school: @school, name: "사서", role: :librarian, password: "password")
    login_as librarian
    get teacher_dashboard_path
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
