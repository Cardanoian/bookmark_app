require "test_helper"

# P7.2 총괄관리자 사용자 관리: 검색·정지/해제·비밀번호 초기화·역할 부여 + 정지 로그인 차단.
class AdminUsersTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "관리학교")
    @classroom = Classroom.create!(school: @school, grade: 6, class_no: 2)
    @superadmin = User.create!(name: "총괄", role: :superadmin, password: "password")
    @student = User.create!(school: @school, classroom: @classroom, name: "김학생", role: :student, password: "password")
  end

  test "index searches by name" do
    User.create!(school: @school, classroom: @classroom, name: "다른아이", role: :student, password: "password")
    login_as @superadmin
    get admin_users_path(q: "김학생")
    assert_response :success
    assert_match "김학생", response.body
    assert_no_match "다른아이", response.body
  end

  test "index filters by role" do
    login_as @superadmin
    get admin_users_path(role: "superadmin")
    assert_response :success
    assert_match "총괄", response.body
    assert_no_match "김학생", response.body
  end

  test "suspend sets suspended true" do
    login_as @superadmin
    post suspend_admin_user_path(@student)
    assert @student.reload.suspended?
  end

  test "unsuspend clears suspended" do
    @student.update!(suspended: true)
    login_as @superadmin
    post unsuspend_admin_user_path(@student)
    assert_not @student.reload.suspended?
  end

  test "reset_password stores a working hashed default password" do
    login_as @superadmin
    post reset_password_admin_user_path(@student)
    @student.reload
    assert @student.authenticate("1234"), "default password should authenticate"
    assert_not_equal "1234", @student.password_digest, "password must be hashed, not plaintext"
  end

  test "role change updates the role" do
    login_as @superadmin
    patch role_admin_user_path(@student), params: { role: "teacher" }
    assert_equal "teacher", @student.reload.role
  end

  test "role change rejects an invalid role" do
    login_as @superadmin
    patch role_admin_user_path(@student), params: { role: "wizard" }
    assert_equal "student", @student.reload.role
  end

  test "a suspended user cannot log in" do
    @student.update!(suspended: true)
    post session_path, params: {
      school_id: @student.school_id, classroom_id: @student.classroom_id,
      name: @student.name, password: "password"
    }
    assert_response :forbidden
    assert_nil session[:user_id]
  end

  test "a user suspended mid-session is logged out on the next request" do
    login_as @student
    get root_path
    assert_response :success

    @student.update!(suspended: true)
    get root_path
    assert_redirected_to new_session_path
  end

  private

  def login_as(user)
    post session_path, params: {
      school_id: user.school_id, classroom_id: user.classroom_id,
      name: user.name, password: "password"
    }
  end
end
