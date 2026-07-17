require "test_helper"

# 학생 상단 navbar가 7개 메뉴 페이지에서 모바일/데스크톱 형태로 유지되는지 확인.
class StudentNavPersistenceTest < ActionDispatch::IntegrationTest
  setup do
    seed_monster_species!
    seed_badges!
    @school = School.create!(name: "네비검증초등학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @student = User.create!(school: @school, classroom: @classroom, name: "네비학생", password: "password")
    login_as @student
  end

  MENU_LABELS = [ "내 서재", "독후감", "게임", "도감", "상점", "미션", "랭킹" ].freeze

  def menu_paths
    [ root_path, reports_path, games_catalog_path, monsters_path, shop_path, missions_path, rankings_path ]
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
          assert_select 'a[aria-current="page"]', text: /#{Regexp.escape(active_label)}/, count: 1
        end
      end
    end

    assert_includes @response.body, "click@window->student-nav#closeFromOutside"
    assert_includes @response.body, "keydown.esc@window->student-nav#close"
    assert_includes @response.body, "turbo:before-cache@document->student-nav#close"
  end

  test "navbar persists across all student menu pages" do
    assert_full_navbar root_path, "내 서재"
    assert_full_navbar reports_path, "독후감"
    assert_full_navbar games_catalog_path, "게임"
    assert_full_navbar monsters_path, "도감"
    assert_full_navbar shop_path, "상점"
    assert_full_navbar missions_path, "미션"
    assert_full_navbar rankings_path, "랭킹"
  end

  test "menu pages do not repeat the active menu as a page heading" do
    [ reports_path, games_catalog_path, monsters_path, shop_path, missions_path, rankings_path ].each do |path|
      get path

      assert_response :success
      assert_select "h1.page-title", count: 0, message: "#{path}에 중복 페이지 제목이 남아 있음"
      assert_select ".page-subtitle", count: 0, message: "#{path}에 페이지 설명이 남아 있음"
    end
  end

  test "report action and shop balance follow the student navbar" do
    get reports_path
    assert_select 'nav[aria-label="학생 메뉴"] + div[data-page-action="new-report"]', count: 1 do
      assert_select "a[href=?]", new_report_path, text: "새 독후감 쓰기", count: 1
    end

    get shop_path
    assert_select 'nav[aria-label="학생 메뉴"] + div[data-page-status="points-balance"]', count: 1 do
      assert_select "#points_balance", text: @student.points.to_s, count: 1
    end
  end

  test "game catalog does not repeat the available game summary" do
    get games_catalog_path

    assert_response :success
    assert_select "h2", text: "즐길 수 있는 게임", count: 0
  end
end
