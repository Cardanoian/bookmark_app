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

  test "every image_key has an installed WebP asset" do
    expected = MonsterSpecies.order(:image_key).pluck(:image_key).map { |key| "#{key}.webp" }
    actual = Rails.root.glob("app/assets/images/monsters/*.webp").map(&:basename).map(&:to_s).sort

    assert_equal 72, expected.size
    assert_equal expected, actual,
                 "installed WebP assets must match all seeded image_keys without missing or stale files"
  end

  test "seeding is idempotent" do
    seed_monster_species!
    assert_equal 72, MonsterSpecies.count
  end

  # unlock_condition 은 라인 단위 규칙이라 stage 1 폼에만 얹혀야 한다(monster_unlocks.md §5).
  test "unlock_condition is set on every stage-1 form and never on stage 2 or 3" do
    assert_equal 24, MonsterSpecies.where(stage: 1).where.not(unlock_condition: nil).count
    assert_equal 0, MonsterSpecies.where(stage: [ 2, 3 ]).where.not(unlock_condition: nil).count
  end

  test "seeded unlock_conditions match docs/monster_unlocks.md for representative lines" do
    assert_equal({ "reports" => 3 }, MonsterSpecies.find_by(key: "pup_1").unlock_condition)
    assert_equal({ "reports" => 6, "max_daily_reports" => 2 }, MonsterSpecies.find_by(key: "parrot_1").unlock_condition)
    assert_equal({ "game_plays" => 8, "distinct_games" => 3 }, MonsterSpecies.find_by(key: "robot_1").unlock_condition)
    assert_equal(
      { "reports" => 20, "a_grades" => 5, "game_books" => 12, "dex_count" => 20 },
      MonsterSpecies.find_by(key: "dragon_1").unlock_condition
    )
  end

  # 부분 시드(phase1)로도 unlock_condition 이 stage1 에만 대입되어야 한다(호환).
  test "phase-1 partial seed also assigns unlock_condition to stage-1 forms only" do
    # 클린 슬레이트: 참조(active_monster·user_monsters)를 먼저 끊고, 자기참조 진화 FK 때문에
    # 자식(상위 stage)부터 지운다. 트랜잭션 테스트라 종료 시 롤백된다.
    User.update_all(active_monster_id: nil)
    UserMonster.delete_all
    MonsterSpecies.where(stage: 3).delete_all
    MonsterSpecies.where(stage: 2).delete_all
    MonsterSpecies.where(stage: 1).delete_all
    MonsterSeeder.seed_phase1!
    assert_operator MonsterSpecies.where(stage: 1).where.not(unlock_condition: nil).count, :>, 0
    assert_equal 0, MonsterSpecies.where(stage: [ 2, 3 ]).where.not(unlock_condition: nil).count
    assert_equal({ "reports" => 3 }, MonsterSpecies.find_by(key: "pup_1").unlock_condition)
  end

  # #misc: 스타터 정합성. YAML 의 starter:true 라인 stage1 키 집합이 코드의
  # MonsterAcquisition::STARTERS 와 정확히 일치해야 한다(과거 4 vs 3 불일치 봉인).
  test "STARTERS matches the seed YAML starter lines (design intent = 3)" do
    yaml = YAML.load_file(Rails.root.join("db/seeds/monsters.yml"))
    starter_stage1_keys = yaml.fetch("monster_lines")
                              .select { |line| line["starter"] == true }
                              .map { |line| line["forms"].find { |f| f["stage"] == 1 }["key"] }

    assert_equal MonsterAcquisition::STARTERS.sort, starter_stage1_keys.sort,
                 "YAML starter:true 라인과 STARTERS 상수가 일치해야 한다"
    assert_equal 3, MonsterAcquisition::STARTERS.size, "스타터는 설계상 3종(pup_1/cat_1/hedgehog_1)"
  end

  # 게임 재구성 골든 불변식(Phase 5 §7·§8): 게이트 도입 후 정상 플레이로 신규 기록 가능한 게임은
  # 4종(quiz·whoami·book·sequel)뿐이다. 어떤 라인의 distinct_games 조건도 4 를 넘으면 정상 플레이로
  # 영구 도달 불가(dead line)이므로, unlock_condition·evolve_condition 양쪽을 전수 검사해 상한 4 를
  # 강제한다. 활성 게임 종류 수가 바뀌면 이 상수와 로스터를 함께 재검토한다.
  test "no distinct_games condition exceeds the active game-type count (4)" do
    active_game_types = 4 # quiz·whoami·book·sequel (GamePlay#game_type 중 정상 플레이 기록 대상)
    MonsterSpecies.find_each do |species|
      [ species.unlock_condition, species.evolve_condition ].each do |condition|
        target = condition&.dig("distinct_games")
        next if target.nil?

        assert_operator target, :<=, active_game_types,
                        "#{species.key} distinct_games:#{target} 는 활성 게임 종류(#{active_game_types})를 넘어 도달 불가"
      end
    end
  end

  # 각 스타터는 실제로 존재하고 서로 다른 속성이어야 한다(선택지 다양성).
  test "every STARTER key seeds a distinct-element stage 1 species" do
    elements = MonsterAcquisition::STARTERS.map do |key|
      species = MonsterSpecies.find_by(key: key)
      assert_not_nil species, "#{key} 스타터 종이 시드돼야 한다"
      assert_equal 1, species.stage
      species.element
    end
    assert_equal elements.size, elements.uniq.size, "스타터는 서로 다른 속성이어야 한다"
  end
end
