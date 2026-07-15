require "test_helper"

class DashboardRoleTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "역할대시초등학교")
    @classroom = Classroom.create!(school: @school, grade: 3, class_no: 1)
  end

  test "student lands on the student dashboard" do
    login_as create_user(name: "역할학생", classroom: @classroom)
    get root_path
    assert_response :success
    assert_select "nav", text: /내 서재/
    assert_match "학생", response.body
  end

  test "teacher lands on the teacher console" do
    teacher = create_user(name: "역할교사", role: :teacher, classroom: @classroom)
    @classroom.update!(teacher: teacher)
    login_as teacher
    get root_path
    assert_response :success
    assert_match "교사 대시보드", response.body
    assert_match "학생관리", response.body
  end

  test "school_admin lands on the school admin dashboard" do
    login_as create_user(name: "역할교무", role: :school_admin, classroom: nil)
    get root_path
    assert_response :success
    assert_match "교무관리자", response.body
  end

  test "librarian lands on the librarian dashboard" do
    login_as create_user(name: "역할사서", role: :librarian, classroom: nil)
    get root_path
    assert_response :success
    assert_match "도서관 담당", response.body
  end

  test "superadmin is redirected to the admin console" do
    admin = User.create!(name: "역할총괄", role: :superadmin, password: "password")
    login_as admin
    get root_path
    assert_redirected_to admin_root_path
    follow_redirect!
    assert_response :success
    assert_match "총괄관리자", response.body
    assert_equal admin.id, session[:user_id]
  end

  private

  def create_user(name:, classroom:, role: :student)
    User.create!(school: @school, classroom: classroom, name: name, role: role, password: "password")
  end
end
