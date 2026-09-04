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

  test "the brand band shows the signed-in student's name and profile link across pages" do
    login_as @student

    get root_path
    assert_response :success
    assert_student_header
    assert_select "h1", text: /님의 서재/, count: 0

    get reports_path
    assert_response :success
    assert_student_header
  end

  test "profile summarizes the signed-in student's activity and account" do
    login_as @student

    get profile_path
    assert_response :success
    assert_select "h1", text: /헤더학생님의 독서 기록/
    assert_select "[aria-labelledby='profile-growth-title']", text: /120XP/
    assert_select "[aria-labelledby='profile-activity-title']", text: /작성한 독후감/
    # 계정 섹션은 비밀번호 변경 진입, 로그아웃은 전역 밴드(app-header)로 이동했다.
    assert_select "[aria-labelledby='profile-account-title'] a[href='#{edit_password_path}']", text: /비밀번호 변경/
    assert_select "header.app-header form[action='#{session_path}']", text: /로그아웃/
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
    # 교직원은 밴드에 학생 계정 컨트롤(마이페이지)이 노출되지 않는다.
    assert_select "header.app-header a[href='#{profile_path}']", count: 0

    get profile_path
    assert_response :forbidden
  end

  private

  # 이름·마이페이지는 전역 밴드(app-header)에 있다(구 학생 서브헤더는 제거됨).
  def assert_student_header
    assert_select "header.app-header", text: /헤더학생/
    assert_select "header.app-header a.btn.btn-secondary[href='#{profile_path}']", text: /마이페이지/, count: 1
    assert_select "header.app-header form[action='#{session_path}'] button.btn.btn-secondary", text: /로그아웃/, count: 1
  end
end
