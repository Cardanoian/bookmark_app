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

  test "student dashboard shows the student's recent reports" do
    school = School.create!(name: "서재초등학교")
    classroom = Classroom.create!(school: school, grade: 3, class_no: 1)
    student = User.create!(school: school, classroom: classroom, name: "서재학생", password: "password")
    other = User.create!(school: school, classroom: classroom, name: "다른학생", password: "password")
    Report.create!(user: student, classroom: classroom, book_title: "내가 읽은 책", body: "내 독후감")
    Report.create!(user: other, classroom: classroom, book_title: "남이 읽은 책", body: "남의 독후감")

    login_as student
    get root_path

    assert_response :success
    assert_select "#recent-reports", text: /내가 읽은 책/
    assert_select "#recent-reports", text: /남이 읽은 책/, count: 0
    assert_select "#recent-reports", text: /아직 읽은 책이 없어요/, count: 0
  end

  test "student dashboard shows the empty state when the student has no reports" do
    school = School.create!(name: "빈서재초등학교")
    classroom = Classroom.create!(school: school, grade: 3, class_no: 1)
    student = User.create!(school: school, classroom: classroom, name: "빈서재학생", password: "password")

    login_as student
    get root_path

    assert_response :success
    assert_select "#recent-reports", text: /아직 읽은 책이 없어요/
  end
end
