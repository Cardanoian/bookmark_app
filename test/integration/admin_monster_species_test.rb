require "test_helper"

# P7.3 몬스터 도감 CRUD + 진화체인 무결성(자기참조 금지·잘못된 JSON 거부).
class AdminMonsterSpeciesTest < ActionDispatch::IntegrationTest
  setup do
    @superadmin = User.create!(name: "총괄", role: :superadmin, password: "password")
    login_as @superadmin
  end

  test "create adds a species" do
    assert_difference -> { MonsterSpecies.count }, 1 do
      post admin_monster_species_index_path, params: { monster_species: {
        key: "admin_pup_1", name: "관리펍", dex_no: 200, stage: 1, element: "story", rarity: "common"
      } }
    end
    assert_equal "관리펍", MonsterSpecies.find_by(key: "admin_pup_1").name
  end

  test "editing an evolve rule persists as parsed JSON" do
    species = MonsterSpecies.create!(key: "evo_1", name: "진화체", dex_no: 201, stage: 1)
    patch admin_monster_species_path(species), params: { monster_species: {
      evolve_condition_json: '{"level": 10, "item": "stone"}'
    } }
    species.reload
    assert_equal({ "level" => 10, "item" => "stone" }, species.evolve_condition)
  end

  test "invalid JSON evolve_condition is rejected (validation error, not a crash)" do
    species = MonsterSpecies.create!(key: "evo_2", name: "진화체2", dex_no: 202, stage: 1)
    patch admin_monster_species_path(species), params: { monster_species: {
      evolve_condition_json: "{not valid json"
    } }
    assert_response :unprocessable_entity
    assert_nil species.reload.evolve_condition
  end

  test "a self-referential evolves_from is rejected" do
    species = MonsterSpecies.create!(key: "evo_3", name: "진화체3", dex_no: 203, stage: 1)
    patch admin_monster_species_path(species), params: { monster_species: {
      evolves_from_id: species.id
    } }
    assert_response :unprocessable_entity
    assert_nil species.reload.evolves_from_id
  end

  test "a species cannot evolve from a same-or-higher stage" do
    stage2 = MonsterSpecies.create!(key: "chain_hi_2", name: "상위", dex_no: 204, stage: 2)
    stage1 = MonsterSpecies.create!(key: "chain_lo_1", name: "하위", dex_no: 204, stage: 1)
    patch admin_monster_species_path(stage1), params: { monster_species: { evolves_from_id: stage2.id } }
    assert_response :unprocessable_entity
    assert_nil stage1.reload.evolves_from_id
  end

  test "destroy removes a species" do
    species = MonsterSpecies.create!(key: "evo_del", name: "삭제체", dex_no: 205, stage: 1)
    assert_difference -> { MonsterSpecies.count }, -1 do
      delete admin_monster_species_path(species)
    end
  end

  private

  def login_as(user)
    post session_path, params: {
      school_id: user.school_id, classroom_id: user.classroom_id,
      name: user.name, password: "password"
    }
  end
end
