require "test_helper"

class AuditLogsTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "감사학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @teacher = User.create!(
      school: @school, classroom: @classroom, name: "감사담임",
      role: :teacher, password: "password"
    )
    @classroom.update!(teacher: @teacher)
    @student = User.create!(school: @school, classroom: @classroom, name: "감사학생", password: "password")
    @superadmin = User.create!(name: "감사총괄", role: :superadmin, password: "password")
  end

  test "teacher point grants and password resets create minimal audit records" do
    login_as @teacher

    assert_difference -> { AuditLog.count }, 2 do
      post give_points_teacher_student_path(@student), params: { points: 15 }
      post reset_password_teacher_student_path(@student), params: { student: { password: "new123" } }
    end

    points_log = AuditLog.find_by!(action: "teacher.points_grant")
    assert_equal @teacher.id, points_log.actor_id
    assert_equal @student.id, points_log.target_id
    assert_equal 15, points_log.metadata["amount"]
    assert_no_match "new123", AuditLog.all.map(&:metadata).to_json
  end

  test "teacher xlsx download is audited without storing the workbook body" do
    Report.create!(user: @student, classroom: @classroom, book_title: "감사책")
    login_as @teacher

    get teacher_exports_reports_xlsx_path

    assert_response :success
    log = AuditLog.find_by!(action: "teacher.reports_xlsx_download")
    assert_equal 1, log.metadata["report_count"]
    assert_not log.metadata.key?("workbook")
    assert_not log.metadata.key?("csv")
  end

  test "superadmin can view audit logs and a student cannot" do
    AuditLog.create!(actor: @teacher, actor_role: @teacher.role, action: "teacher.points_grant")

    login_as @superadmin
    get admin_audit_logs_path
    assert_response :success
    assert_match "학생 포인트 지급", response.body

    login_as @student
    get admin_audit_logs_path
    assert_response :forbidden
  end
end
