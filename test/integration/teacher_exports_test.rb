require "test_helper"

# P6.3 CSV 내보내기(대회요건 연구06): 사전·사후 5축 비교 원자료.
class TeacherExportsTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "내보내기학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @teacher = User.create!(school: @school, classroom: @classroom, name: "내보담임", role: :teacher, password: "password")
    @classroom.update!(teacher: @teacher)
    @student = User.create!(school: @school, classroom: @classroom, name: "내보학생", password: "password")

    @original = Report.create!(
      user: @student, classroom: @classroom, book_title: "원본책",
      rubric: { "content" => 3, "emotion" => 3, "life" => 3, "structure" => 3, "spelling" => 3 },
      avg: 3.0, level: "B", ai_status: :done
    )
    @revision = Report.create!(
      user: @student, classroom: @classroom, book_title: "원본책",
      rubric: { "content" => 5, "emotion" => 5, "life" => 5, "structure" => 4, "spelling" => 4 },
      avg: 4.6, level: "A", ai_status: :done,
      revision_of: @original, prev_avg: 3.0, improvement: 1.6
    )
  end

  test "reports_csv returns text/csv with 사전·사후 5축 columns" do
    login_as @teacher
    get teacher_exports_reports_csv_path

    assert_response :success
    assert_equal "text/csv", response.media_type

    body = response.body
    assert_match "사전", body
    assert_match "사후", body
    ReadingDomain::AXIS_LABELS.each_value { |label| assert_match label, body }
    assert_match @student.name, body
  end

  test "reports_csv includes both the original and the revised 5축 rows" do
    login_as @teacher
    get teacher_exports_reports_csv_path

    body = response.body
    assert_match "3.0", body   # 사전 평균
    assert_match "4.6", body   # 사후 평균
    assert_match "1.6", body   # 향상도
  end

  test "a student is forbidden from the CSV export" do
    login_as @student
    get teacher_exports_reports_csv_path
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
