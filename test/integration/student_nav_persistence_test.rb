require "test_helper"

# 임시 검증: 학생 상단 navbar가 7개 메뉴 페이지 전체에서 렌더되는지 확인.
class StudentNavPersistenceTest < ActionDispatch::IntegrationTest
  setup do
    seed_monster_species!
    seed_badges!
    @school = School.create!(name: "네비검증초등학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @student = User.create!(school: @school, classroom: @classroom, name: "네비학생", password: "password")
    login_as @student
  end

  MENU_LABELS = %w[내 서재 독후감 게임 도감 상점 미션 랭킹].freeze

  def assert_full_navbar(path)
    get path
    assert_response :success, "#{path} 응답 실패"
    MENU_LABELS.each do |label|
      assert_includes @response.body, label, "#{path} 에 '#{label}' 메뉴가 없음"
    end
    # 활성 탭 강조: 반응형 필 내비 개편으로 표시자가 amber 밑줄 → 검은 필 + aria-current 로 바뀜.
    # 구현 세부(색 클래스) 대신 접근성 시맨틱 마커로 검증(더 견고).
    assert_includes @response.body, 'aria-current="page"', "#{path} 에 활성 탭 강조가 없음"
  end

  test "navbar persists across all student menu pages" do
    assert_full_navbar root_path          # 내 서재 (dashboard)
    assert_full_navbar reports_path       # 독후감
    assert_full_navbar games_catalog_path # 게임
    assert_full_navbar monsters_path      # 도감
    assert_full_navbar shop_path          # 상점
    assert_full_navbar missions_path      # 미션
    assert_full_navbar rankings_path      # 랭킹
  end
end
