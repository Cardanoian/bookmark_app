require "test_helper"

class StudentHeaderProfileTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "공통헤더초등학교")
    @classroom = Classroom.create!(school: @school, grade: 4, class_no: 2)
    @student = User.create!(
      school: @school,
      classroom: @classroom,
      name: "헤더학생",
      password: "password",
      points: 120
    )
  end

  test "student header shows the student name, back link, and profile link across pages" do
    login_as @student

    get root_path
    assert_response :success
    assert_student_header(back_path: root_path)
    assert_select "h1", text: /님의 서재/, count: 0

    get reports_path, headers: { "HTTP_REFERER" => root_url }
    assert_response :success
    assert_student_header(back_path: root_path)
  end

  test "profile summarizes the signed-in student's activity and account" do
    login_as @student

    get profile_path
    assert_response :success
    assert_select "h1", text: /헤더학생님의 독서 기록/
    assert_select "[aria-labelledby='profile-activity-title']", text: /작성한 독후감/
    assert_select "[aria-labelledby='profile-account-title'] form[action='#{session_path}']"
    assert_select "a[aria-current='page'][href='#{profile_path}']", text: /마이페이지/
  end

  test "staff does not see the student header and cannot open a student profile" do
    teacher = User.create!(
      school: @school,
      classroom: @classroom,
      name: "헤더교사",
      role: :teacher,
      password: "password"
    )
    login_as teacher

    get root_path
    assert_response :success
    assert_select "header[aria-label='학생 공통 헤더']", count: 0

    get profile_path
    assert_response :forbidden
  end

  private

  def assert_student_header(back_path:)
    assert_select "header[aria-label='학생 공통 헤더']", count: 1 do
      assert_select "p", text: "헤더학생", count: 1
      assert_select "a[aria-label='뒤로 가기'][href='#{back_path}']", count: 1
      assert_select "a[href='#{profile_path}']", text: /마이페이지/, count: 1
    end
  end
end
