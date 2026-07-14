require "test_helper"

class DashboardAccessTest < ActionDispatch::IntegrationTest
  test "unauthenticated request to root redirects to login" do
    get root_path
    assert_redirected_to new_session_path
  end

  test "authenticated user can reach the dashboard" do
    school = School.create!(name: "대시초등학교")
    classroom = Classroom.create!(school: school, grade: 3, class_no: 1)
    student = User.create!(school: school, classroom: classroom, name: "대시학생", password: "password")

    login_as student
    get root_path

    assert_response :success
    assert_match "대시학생", response.body
  end
end
