require "test_helper"

# 학생 상단 navbar가 5개 메뉴 페이지(menu_refactor 심화 PR5)에서 모바일/데스크톱 형태로 유지되는지 확인.
class StudentNavPersistenceTest < ActionDispatch::IntegrationTest
  setup do
    seed_monster_species!
    seed_badges!
    @school = School.create!(name: "네비검증초등학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @student = User.create!(school: @school, classroom: @classroom, name: "네비학생", password: "password")
    login_as @student
  end

  MENU_LABELS = [ "홈", "내 서재", "독서활동", "도감", "나의 성장" ].freeze

  def menu_paths
    [ root_path, library_path, reading_activity_path, monsters_path, growth_path ]
  end

  def assert_full_navbar(path, active_label)
    get path
    assert_response :success, "#{path} 응답 실패"

    assert_select 'nav[aria-label="학생 메뉴"][data-controller="student-nav"]', count: 1 do
      assert_select 'details[data-student-nav-target="menu"]', count: 1
      assert_select 'summary[data-student-nav-target="summary"][aria-controls="student-mobile-menu"]',
        text: /#{Regexp.escape(active_label)}/, count: 1

      %w[mobile desktop].each do |layout|
        assert_select "ul[data-student-nav-layout='#{layout}']", count: 1 do
          assert_select "a", count: MENU_LABELS.size do |links|
            assert_equal menu_paths, links.map { |link| link["href"] },
              "#{path} #{layout} 메뉴 경로가 공용 순서와 다름"
          end
          MENU_LABELS.each do |label|
            assert_select "a", text: /#{Regexp.escape(label)}/, count: 1,
              message: "#{path} #{layout} 메뉴에 '#{label}' 링크가 없음"
          end
          assert_select 'a[aria-current="page"].bg-surface-featured.text-blue-pressed',
            text: /#{Regexp.escape(active_label)}/, count: 1
          assert_select 'a[aria-current="page"].bg-primary', count: 0,
            message: "#{path} #{layout} 활성 메뉴에 검은 배경이 남아 있음"
        end
      end
    end

    assert_includes @response.body, "click@window->student-nav#closeFromOutside"
    assert_includes @response.body, "keydown.esc@window->student-nav#close"
    assert_includes @response.body, "turbo:before-cache@document->student-nav#close"
  end

  test "navbar persists across all student menu pages" do
    assert_full_navbar root_path, "홈"
    assert_full_navbar library_path, "내 서재"
    assert_full_navbar reading_activity_path, "독서활동"
    assert_full_navbar monsters_path, "도감"
    assert_full_navbar growth_path, "나의 성장"
  end

  test "menu pages do not repeat the active menu as an h1 page heading" do
    [ library_path, reading_activity_path, monsters_path ].each do |path|
      get path

      assert_response :success
      assert_select "h1.page-title", count: 0, message: "#{path}에 중복 h1 페이지 제목이 남아 있음"
    end
  end

  test "report action follows the student navbar" do
    get reports_path
    assert_select 'nav[aria-label="학생 메뉴"] + div[data-page-action="new-report"]', count: 1 do
      assert_select "a[href=?]", new_report_path, text: "새 독후감 쓰기", count: 1
    end
  end

  test "game catalog does not repeat the available game summary" do
    get games_catalog_path

    assert_response :success
    assert_select "h2", text: "즐길 수 있는 게임", count: 0
  end
end
