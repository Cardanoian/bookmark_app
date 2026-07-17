require "test_helper"

class MonsterSpeciesTest < ActiveSupport::TestCase
  test "element enum defines six values" do
    assert_equal(
      { "story" => 0, "knowledge" => 1, "emotion" => 2, "adventure" => 3, "nature" => 4, "imagination" => 5 },
      MonsterSpecies.elements
    )
  end

  test "rarity enum defines three values" do
    assert_equal({ "common" => 0, "rare" => 1, "epic" => 2 }, MonsterSpecies.rarities)
  end

  test "key must be unique" do
    MonsterSpecies.create!(key: "unique_1", stage: 1, dex_no: 99)
    dup = MonsterSpecies.new(key: "unique_1", stage: 1, dex_no: 100)
    assert_not dup.valid?
    assert dup.errors[:key].any?
  end

  test "key is required" do
    assert_not MonsterSpecies.new(stage: 1).valid?
  end

  test "self-referential evolution chain links stages" do
    stage1 = MonsterSpecies.create!(key: "chain_1", stage: 1, dex_no: 90)
    stage2 = MonsterSpecies.create!(key: "chain_2", stage: 2, dex_no: 90, evolves_from: stage1)
    stage3 = MonsterSpecies.create!(key: "chain_3", stage: 3, dex_no: 90, evolves_from: stage2)

    assert_nil stage1.evolves_from
    assert_equal stage1, stage2.evolves_from
    assert_includes stage1.next_forms, stage2
    assert_equal stage2, stage1.next_form
    assert_equal stage3, stage2.next_form
    assert_nil stage3.next_form
  end

  test "element and rarity accept string labels from seed" do
    species = MonsterSpecies.create!(key: "story_common", stage: 1, dex_no: 91, element: "story", rarity: "common")
    assert species.story?
    assert species.common?
  end

  # P1.5 방어 심화 — evolve_condition 키를 화이트리스트로 강제해, 오타 키가 학생 도감(evolvable?)에서
  # 500 나기 전에 저장 시점에 막는다.
  test "evolve_condition with a whitelisted key is accepted" do
    species = MonsterSpecies.new(key: "cond_ok_1", stage: 1, dex_no: 300, evolve_condition: { "points" => 100, "reports" => 3 })
    assert species.valid?, species.errors.full_messages.to_sentence
  end

  test "evolve_condition with a badge key is accepted" do
    species = MonsterSpecies.new(key: "cond_badge_1", stage: 1, dex_no: 301, evolve_condition: { "badge" => "reviser" })
    assert species.valid?, species.errors.full_messages.to_sentence
  end

  test "evolve_condition with an unknown key is rejected" do
    species = MonsterSpecies.new(key: "cond_bad_1", stage: 1, dex_no: 302, evolve_condition: { "reprots" => 3 })
    assert_not species.valid?
    assert species.errors[:evolve_condition].any?
  end

  test "evolve_condition with a non-integer numeric target is rejected" do
    species = MonsterSpecies.new(key: "cond_bad_2", stage: 1, dex_no: 303, evolve_condition: { "points" => "many" })
    assert_not species.valid?
    assert species.errors[:evolve_condition].any?
  end

  test "evolve_condition with a negative numeric target is rejected" do
    species = MonsterSpecies.new(key: "cond_bad_3", stage: 1, dex_no: 304, evolve_condition: { "points" => -5 })
    assert_not species.valid?
    assert species.errors[:evolve_condition].any?
  end

  test "an unknown key entered via the JSON writer is rejected as a validation error, not a crash" do
    species = MonsterSpecies.new(key: "cond_json_bad", stage: 1, dex_no: 305)
    species.evolve_condition_json = '{"level": 10}'
    assert_not species.valid?
    assert species.errors[:evolve_condition].any?
  end

  test "blank evolve_condition (stage 3) is valid" do
    species = MonsterSpecies.new(key: "cond_blank", stage: 3, dex_no: 306)
    assert species.valid?, species.errors.full_messages.to_sentence
  end

  # 시더가 적재하는 모든 실제 진화 조건이 새 화이트리스트 검증을 통과해야 한다(회귀 방지).
  test "all seeded evolve_conditions satisfy the key whitelist" do
    seed_monster_species!
    MonsterSpecies.where.not(evolve_condition: nil).find_each do |species|
      assert species.valid?, "#{species.key}: #{species.errors.full_messages.to_sentence}"
    end
  end

  # unlock_condition 검증 — evolve_condition 검증자를 미러링(같은 화이트리스트·정수·JSON 규칙).
  test "unlock_condition with whitelisted keys is accepted" do
    species = MonsterSpecies.new(key: "unlock_ok_1", stage: 1, dex_no: 310,
                                 unlock_condition: { "reports" => 6, "max_daily_reports" => 2 })
    assert species.valid?, species.errors.full_messages.to_sentence
  end

  test "unlock_condition with a game metric key is accepted" do
    species = MonsterSpecies.new(key: "unlock_ok_2", stage: 1, dex_no: 311,
                                 unlock_condition: { "game_plays" => 8, "distinct_games" => 3, "game_books" => 5 })
    assert species.valid?, species.errors.full_messages.to_sentence
  end

  test "unlock_condition with an unknown key is rejected" do
    species = MonsterSpecies.new(key: "unlock_bad_1", stage: 1, dex_no: 312, unlock_condition: { "reprots" => 3 })
    assert_not species.valid?
    assert species.errors[:unlock_condition].any?
  end

  test "unlock_condition with a negative target is rejected" do
    species = MonsterSpecies.new(key: "unlock_bad_2", stage: 1, dex_no: 313, unlock_condition: { "reports" => -1 })
    assert_not species.valid?
    assert species.errors[:unlock_condition].any?
  end

  test "unlock_condition with a non-integer target is rejected" do
    species = MonsterSpecies.new(key: "unlock_bad_3", stage: 1, dex_no: 314, unlock_condition: { "reports" => "many" })
    assert_not species.valid?
    assert species.errors[:unlock_condition].any?
  end

  test "unlock_condition that is not a hash is rejected" do
    species = MonsterSpecies.new(key: "unlock_bad_4", stage: 1, dex_no: 315, unlock_condition: [ "reports", 3 ])
    assert_not species.valid?
    assert species.errors[:unlock_condition].any?
  end

  test "an unknown key entered via the unlock JSON writer is a validation error, not a crash" do
    species = MonsterSpecies.new(key: "unlock_json_bad", stage: 1, dex_no: 316)
    species.unlock_condition_json = '{"level": 10}'
    assert_not species.valid?
    assert species.errors[:unlock_condition].any?
  end

  test "invalid unlock JSON is a validation error, not a crash" do
    species = MonsterSpecies.new(key: "unlock_json_broken", stage: 1, dex_no: 317)
    species.unlock_condition_json = "{not json"
    assert_not species.valid?
    assert species.errors[:unlock_condition].any?
  end

  # 시더가 적재하는 모든 실제 해금 조건(stage1)이 화이트리스트 검증을 통과해야 한다.
  test "all seeded unlock_conditions satisfy the key whitelist" do
    seed_monster_species!
    MonsterSpecies.where.not(unlock_condition: nil).find_each do |species|
      assert species.valid?, "#{species.key}: #{species.errors.full_messages.to_sentence}"
    end
  end
end
