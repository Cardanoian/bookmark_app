require "test_helper"

# P6.3 인쇄 문서: 표창장·가정통신문·포트폴리오·학급 성장 리포트(print 레이아웃).
class TeacherPrintsTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "인쇄학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @teacher = User.create!(school: @school, classroom: @classroom, name: "인쇄담임", role: :teacher, password: "password")
    @classroom.update!(teacher: @teacher)
    @student = User.create!(school: @school, classroom: @classroom, name: "인쇄학생", password: "password")
    Report.create!(
      user: @student, classroom: @classroom, book_title: "인쇄책",
      rubric: { "content" => 4, "emotion" => 4, "life" => 4, "structure" => 3, "spelling" => 3 },
      avg: 3.7, level: "A", ai_status: :done
    )
  end

  test "award renders 200 with the print layout" do
    login_as @teacher
    get award_teacher_prints_path(student_id: @student.id)
    assert_response :success
    assert_match "표 창 장", response.body
    assert_match "인쇄하기", response.body # print layout toolbar
  end

  test "home_letter renders 200 with the print layout" do
    login_as @teacher
    get home_letter_teacher_prints_path(student_id: @student.id)
    assert_response :success
    assert_match "가정통신문", response.body
    assert_match "인쇄하기", response.body
  end

  test "portfolio renders 200 with a radar svg" do
    login_as @teacher
    get portfolio_teacher_prints_path(student_id: @student.id)
    assert_response :success
    assert_match "<svg", response.body
    assert_match "<polygon", response.body
    assert_match "인쇄하기", response.body
  end

  test "class_report renders 200 with the print layout" do
    login_as @teacher
    get class_report_teacher_prints_path(classroom_id: @classroom.id)
    assert_response :success
    assert_match "학급 성장 리포트", response.body
    assert_match "인쇄하기", response.body
  end

  test "a student is forbidden from print documents" do
    login_as @student
    get award_teacher_prints_path(student_id: @student.id)
    assert_response :forbidden
  end

  test "a non-담임 teacher cannot print another classroom's student" do
    other_classroom = Classroom.create!(school: @school, grade: 5, class_no: 2)
    other_teacher = User.create!(school: @school, classroom: other_classroom, name: "인쇄타담임", role: :teacher, password: "password")
    other_classroom.update!(teacher: other_teacher)

    login_as other_teacher
    get award_teacher_prints_path(classroom_id: @classroom.id, student_id: @student.id)
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
