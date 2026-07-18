require "test_helper"

# 학생 공통 헤더의 뒤로가기 버튼이 "이전 페이지(referer)"가 아니라 현재 화면의
# 컨트롤러/액션 기준 "상위 메뉴"를 가리키는지 검증한다(application_helper#student_back_path).
class StudentBackNavigationTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "뒤로가기초등학교")
    @classroom = Classroom.create!(school: @school, grade: 4, class_no: 1)
    @student = User.create!(
      school: @school,
      classroom: @classroom,
      name: "뒤로가기학생",
      password: "password"
    )
    login_as @student
  end

  # 자식 화면 → 상위 메뉴 링크. 외부 referer 를 줘도 무시하고 상위 메뉴를 가리킨다
  # (구 referer 기반 구현의 외부 이탈 차단이 새 방식에서도 유지되는지 함께 확인).
  {
    "/reports/new"      => "/reports", # 새 독후감 → 독후감 목록
    "/profile/password" => "/profile", # 비밀번호 변경 → 마이페이지
    "/profile"          => "/"         # 마이페이지 → 내 서재
  }.each do |from, expected_back|
    test "back link from #{from} points to #{expected_back}" do
      get from, headers: { "HTTP_REFERER" => "https://evil.example.com/x" }
      assert_response :success
      assert_select "header[aria-label='학생 공통 헤더'] a[aria-label='뒤로 가기'][href='#{expected_back}']", 1
    end
  end

  # 최상위 목록 화면 → 뒤로가기가 내 서재(root)를 가리킨다.
  test "back link from reports index points to home" do
    get reports_path, headers: { "HTTP_REFERER" => "https://evil.example.com/x" }
    assert_response :success
    assert_select "header[aria-label='학생 공통 헤더'] a[aria-label='뒤로 가기'][href='#{root_path}']", 1
  end

  test "back link from games catalog points to home" do
    get games_catalog_path
    assert_response :success
    assert_select "header[aria-label='학생 공통 헤더'] a[aria-label='뒤로 가기'][href='#{root_path}']", 1
  end

  # 상위가 자기 자신인 화면(내 서재=홈)은 뒤로가기 버튼을 숨기고 스페이서만 둔다.
  test "back link is hidden on dashboard home (/)" do
    get root_path
    assert_response :success
    assert_select "header[aria-label='학생 공통 헤더']" do
      assert_select "a[aria-label='뒤로 가기']", count: 0
      assert_select "span.invisible", count: 1
    end
  end
end
