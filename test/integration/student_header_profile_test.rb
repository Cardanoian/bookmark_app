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

    # 내 서재(홈)는 상위가 자기 자신이라 뒤로가기 버튼을 숨긴다(back_path: nil).
    get root_path
    assert_response :success
    assert_student_header(back_path: nil)
    assert_select "h1", text: /님의 서재/, count: 0

    # 독후감 목록은 최상위 메뉴라 뒤로가기가 내 서재로 향한다.
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
    # 계정 섹션은 비밀번호 변경 진입, 로그아웃은 공통 헤더로 이동했다(WS-G).
    assert_select "[aria-labelledby='profile-account-title'] a[href='#{edit_password_path}']", text: /비밀번호 변경/
    assert_select "header[aria-label='학생 공통 헤더'] form[action='#{session_path}']", text: /로그아웃/
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

  # back_path: 경로면 그 href 로 향하는 뒤로가기 링크를, nil 이면 링크 부재 +
  # 레이아웃 유지용 스페이서(span.invisible) 존재를 단언한다.
  def assert_student_header(back_path:)
    assert_select "header[aria-label='학생 공통 헤더']", count: 1 do
      assert_select "p", text: "헤더학생", count: 1
      if back_path
        assert_select "a[aria-label='뒤로 가기'][href='#{back_path}']", count: 1
      else
        assert_select "a[aria-label='뒤로 가기']", count: 0
        assert_select "span.invisible", count: 1
      end
      assert_select "a[href='#{profile_path}']", text: /마이페이지/, count: 1
    end
  end
end
