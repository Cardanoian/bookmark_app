require "test_helper"

# P4.5 — 스타터 선택 온보딩(가챠/랜덤 없음, 노력 기반 획득).
class StarterSelectionTest < ActionDispatch::IntegrationTest
  setup do
    seed_monster_species!
    seed_badges!
    @school = School.create!(name: "스타터초등학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @student = User.create!(school: @school, classroom: @classroom, name: "스타터학생", password: "password")
  end

  test "student with no monster sees the onboarding prompt on the dashboard" do
    login_as @student
    get root_path
    assert_response :success
    assert_match "첫 반려 몬스터", response.body
  end

  test "choosing a starter creates the monster and sets it active" do
    login_as @student

    assert_difference -> { @student.user_monsters.count }, 1 do
      post choose_starter_monsters_path, params: { key: "pup_1" }
    end

    monster = @student.user_monsters.last
    assert_equal "pup_1", monster.monster_species.key
    assert_equal monster.id, @student.reload.active_monster_id
    assert_redirected_to monster_path(monster.dex_no)
  end

  test "an invalid (non-starter) key is rejected" do
    login_as @student

    assert_no_difference -> { @student.user_monsters.count } do
      post choose_starter_monsters_path, params: { key: "dragon_1" }
    end
    assert_redirected_to monsters_path
  end

  test "a student who already owns a monster cannot pick another starter" do
    MonsterAcquisition.new(@student).choose_starter!("pup_1")
    login_as @student

    assert_no_difference -> { @student.user_monsters.count } do
      post choose_starter_monsters_path, params: { key: "cat_1" }
    end
    assert_redirected_to monsters_path
  end

  test "no gacha or random acquisition route exists" do
    Rails.application.routes.routes.each do |route|
      assert_no_match(/gacha|random|gamble|draw|roll|loot/i, route.path.spec.to_s)
    end
  end

  private
end
