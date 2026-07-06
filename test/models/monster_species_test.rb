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
end
