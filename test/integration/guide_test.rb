require "test_helper"

# 사용방법 안내(학생 도움말) — 상단 메뉴 노출 + 정적 화면 렌더 + 학생 게이트.
class GuideTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "안내초등학교")
    @classroom = Classroom.create!(school: @school, grade: 3, class_no: 1)
    @student = User.create!(school: @school, classroom: @classroom, name: "안내학생", password: "password")
    login_as @student
  end

  test "학생 상단 메뉴에 사용방법이 있고 안내 화면으로 연결된다" do
    get root_path
    assert_response :success
    assert_select "nav[aria-label='학생 메뉴'] span", text: "사용방법"
    assert_select "nav[aria-label='학생 메뉴'] a[href=?]", guide_path
  end

  test "사용방법 화면은 앱 흐름과 각 메뉴 진입점을 안내한다" do
    get guide_path
    assert_response :success
    assert_select "h1", text: "책갈피 사용방법"
    # 흐름 안내의 핵심 진입점(독서활동·도감·성장·마이페이지)이 실제 링크로 걸려 있다.
    [ reading_activity_path, library_path, monsters_path, growth_path, profile_path ].each do |path|
      assert_select "a[href=?]", path
    end
  end

  test "안내 문구의 수치·명칭은 도메인 상수에서 파생한다" do
    get guide_path
    assert_response :success
    # 5축 라벨 + 학년군(3학년 → g34) 눈높이 설명
    ReadingDomain::RUBRIC_AXES.each do |axis|
      assert_match ReadingDomain::AXIS_LABELS.fetch(axis), response.body
    end
    assert_match ReadingDomain::AXIS_MEANINGS_BY_BAND[:g34][:content], response.body
    # 등급별 포인트 · 퀴즈 정답당 포인트 · 게임 4종 이름
    ReadingDomain::LEVEL_POINTS.each_value { |points| assert_match "#{points}P", response.body }
    assert_match "#{Games::QuestionScorer::POINTS_PER_CORRECT}P", response.body
    Games::BaseController::CATALOG.each_value { |meta| assert_match meta[:name], response.body }
  end

  test "학생 대면 문구는 첨삭 주체를 선생님으로 부른다" do
    get guide_path
    assert_response :success
    assert_no_match "AI 선생님", response.body
  end

  test "비학생은 사용방법 화면에서 홈으로 돌아가고 메뉴에도 노출되지 않는다" do
    delete session_path
    teacher = User.create!(school: @school, classroom: @classroom, name: "안내교사",
                           email: "guide_t@example.com", role: :teacher, password: "password")
    login_as teacher

    get guide_path
    assert_redirected_to root_path

    get root_path
    assert_response :success
    assert_select "nav[aria-label='학생 메뉴']", count: 0
  end
end
