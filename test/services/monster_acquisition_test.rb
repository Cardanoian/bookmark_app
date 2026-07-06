require "test_helper"

class MonsterAcquisitionTest < ActiveSupport::TestCase
  setup do
    seed_monster_species!
    @school = School.create!(name: "획득초등학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @user = User.create!(school: @school, classroom: @classroom, name: "획득학생", password: "password")
    @acq = MonsterAcquisition.new(@user)
  end

  test "STARTERS are the three documented starter keys" do
    assert_equal %w[pup_1 cat_1 hedgehog_1], MonsterAcquisition::STARTERS
  end

  test "choose_starter! creates a stage-1 user_monster and sets active monster" do
    monster = @acq.choose_starter!("cat_1")
    assert_equal "cat_1", monster.monster_species.key
    assert_equal 5, monster.dex_no
    assert monster.obtained_at.present?
    assert_equal monster, @user.reload.active_monster
  end

  test "choose_starter! rejects an invalid (non-starter) key" do
    assert_raises(MonsterAcquisition::InvalidStarter) { @acq.choose_starter!("owl_1") }
    assert_raises(MonsterAcquisition::InvalidStarter) { @acq.choose_starter!("nonexistent") }
    assert_equal 0, @user.user_monsters.count
  end

  test "choose_starter! rejects choosing a second starter on the same line" do
    @acq.choose_starter!("pup_1")
    assert_raises(MonsterAcquisition::AlreadyOwned) { @acq.choose_starter!("pup_1") }
  end

  test "discover_monster! adds a new stage-1 monster by dex_no" do
    monster = @acq.discover_monster!(13)
    assert_equal "bear_1", monster.monster_species.key
    assert_equal 13, monster.dex_no
  end

  test "discover_monster! accepts a species key and adds the line's stage-1 form" do
    monster = @acq.discover_monster!("hamster_1")
    assert_equal "hamster_1", monster.monster_species.key
    assert_equal 9, monster.dex_no
  end

  test "discover_monster! is a no-op when the line is already owned" do
    @acq.discover_monster!(13)
    assert_nil @acq.discover_monster!(13)
    assert_equal 1, @user.user_monsters.where(dex_no: 13).count
  end

  test "discover_monster! returns nil for an unknown line" do
    assert_nil @acq.discover_monster!(999)
    assert_nil @acq.discover_monster!("no_such_key")
  end

  test "no gacha / random acquisition path exists" do
    forbidden = %i[gacha draw roll random pull spin lottery]
    forbidden.each do |name|
      assert_not_includes MonsterAcquisition.instance_methods, name
      assert_not_includes MonsterAcquisition.public_instance_methods, name
    end
    source = File.read(Rails.root.join("app/services/monster_acquisition.rb"))
    refute_match(/\brand\b|\.sample\b|SecureRandom|shuffle/, source)
  end
end
