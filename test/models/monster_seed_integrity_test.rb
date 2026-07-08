require "test_helper"

# Verifies the real `monsters:seed` rake task loads docs/monsters.md §7 correctly.
class MonsterSeedIntegrityTest < ActiveSupport::TestCase
  setup { seed_monster_species! }

  test "seeds exactly 72 forms (24 lines x 3 stages)" do
    assert_equal 72, MonsterSpecies.count
    assert_equal 24, MonsterSpecies.distinct.count(:dex_no)
  end

  test "seeds all 24 dex_no lines 1..24 (both phases)" do
    assert_equal (1..24).to_a, MonsterSpecies.distinct.order(:dex_no).pluck(:dex_no)
  end

  test "every seeded line has stages 1, 2 and 3" do
    MonsterSpecies.distinct.pluck(:dex_no).each do |dex_no|
      stages = MonsterSpecies.where(dex_no: dex_no).order(:stage).pluck(:stage)
      assert_equal [ 1, 2, 3 ], stages, "dex #{dex_no} should have stages 1,2,3"
    end
  end

  test "evolves_from chain is wired stage 1 -> 2 -> 3 within each line" do
    MonsterSpecies.distinct.pluck(:dex_no).each do |dex_no|
      forms = MonsterSpecies.where(dex_no: dex_no).order(:stage).to_a
      assert_nil forms[0].evolves_from, "dex #{dex_no} stage 1 should have no parent"
      assert_equal forms[0], forms[1].evolves_from
      assert_equal forms[1], forms[2].evolves_from
    end
  end

  test "stage 3 forms have no evolve_condition" do
    MonsterSpecies.where(stage: 3).each do |species|
      assert species.evolve_condition.blank?, "#{species.key} (stage 3) should have no evolve_condition"
    end
  end

  test "pup line evolve_condition matches docs/monsters.md" do
    assert_equal({ "points" => 100, "reports" => 3 }, MonsterSpecies.find_by(key: "pup_1").evolve_condition)
    assert_equal(
      { "points" => 450, "a_grades" => 1, "b_or_better" => 5 },
      MonsterSpecies.find_by(key: "pup_2").evolve_condition
    )
    assert_equal "story", MonsterSpecies.find_by(key: "pup_1").element
    assert_equal "common", MonsterSpecies.find_by(key: "pup_1").rarity
  end

  test "cat line 1->2 condition matches docs/monsters.md" do
    assert_equal({ "points" => 100, "distinct_genres" => 2 }, MonsterSpecies.find_by(key: "cat_1").evolve_condition)
  end

  test "phase 2 lines are seeded (dragon line present with docs conditions)" do
    dragon1 = MonsterSpecies.find_by(key: "dragon_1")
    assert_equal 24, dragon1.dex_no
    assert_equal "imagination", dragon1.element
    assert_equal "epic", dragon1.rarity
    assert_equal({ "points" => 250, "dex_count" => 5 }, dragon1.evolve_condition)
    assert_equal(
      { "points" => 1000, "dex_count" => 10, "a_grades" => 3, "classics" => 2 },
      MonsterSpecies.find_by(key: "dragon_2").evolve_condition
    )
  end

  test "image_key equals the form key" do
    species = MonsterSpecies.find_by(key: "hedgehog_1")
    assert_equal "hedgehog_1", species.image_key
  end

  test "seeding is idempotent" do
    seed_monster_species!
    assert_equal 72, MonsterSpecies.count
  end
end
