require "test_helper"

class UserMonsterTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "몬스터초등학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @user = User.create!(school: @school, classroom: @classroom, name: "몬스터학생", password: "password")
    @species = MonsterSpecies.create!(key: "um_pup_1", stage: 1, dex_no: 1, element: "story", rarity: "common")
  end

  test "belongs to user and monster_species" do
    monster = @user.user_monsters.create!(monster_species: @species, obtained_at: Time.current)
    assert_equal @user, monster.user
    assert_equal @species, monster.monster_species
    assert_equal @species, monster.species
  end

  test "dex_no is auto-set from species on create" do
    monster = @user.user_monsters.create!(monster_species: @species, obtained_at: Time.current)
    assert_equal 1, monster.dex_no
  end

  test "dex_no is unique per user (one row per line, in-place evolution)" do
    @user.user_monsters.create!(monster_species: @species, dex_no: 1, obtained_at: Time.current)
    duplicate = @user.user_monsters.build(monster_species: @species, dex_no: 1, obtained_at: Time.current)
    assert_not duplicate.valid?
    assert duplicate.errors[:dex_no].any?
  end

  test "same dex_no is allowed for a different user" do
    other = User.create!(school: @school, classroom: @classroom, name: "다른학생", password: "password")
    @user.user_monsters.create!(monster_species: @species, dex_no: 1, obtained_at: Time.current)
    assert other.user_monsters.build(monster_species: @species, dex_no: 1, obtained_at: Time.current).valid?
  end
end
