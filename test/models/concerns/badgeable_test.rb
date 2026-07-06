require "test_helper"

class BadgeableTest < ActiveSupport::TestCase
  setup do
    seed_badges!
    @school = School.create!(name: "뱃지초등학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @user = User.create!(school: @school, classroom: @classroom, name: "뱃지학생", password: "password")
  end

  def report(attrs = {})
    Report.create!({ user: @user, classroom: @classroom, book_title: "책" }.merge(attrs))
  end

  def keys
    @user.badges.reload.pluck(:key)
  end

  test "first / three / ten granted by reviewed report counts" do
    3.times { report(reviewed: true) }
    @user.refresh_badges!
    assert_includes keys, "first"
    assert_includes keys, "three"
    assert_not_includes keys, "ten"
  end

  test "levelA and tripleA granted by A-grade counts" do
    3.times { report(level: "A") }
    @user.refresh_badges!
    assert_includes keys, "levelA"
    assert_includes keys, "tripleA"
  end

  test "reviser granted when an improved revision exists" do
    report(improvement: 2.0)
    @user.refresh_badges!
    assert_includes keys, "reviser"
  end

  test "challenger granted by challenge participation" do
    challenge = Challenge.create!(title: "챌린지")
    report(challenge_id: challenge.id)
    @user.refresh_badges!
    assert_includes keys, "challenger"
  end

  test "ocr granted when an OCR report exists" do
    report(input_mode: :ocr)
    @user.refresh_badges!
    assert_includes keys, "ocr"
  end

  test "badges are idempotent (no duplicates on repeat refresh)" do
    report(reviewed: true)
    @user.refresh_badges!
    @user.refresh_badges!
    assert_equal 1, @user.user_badges.where(badge: Badge.find_by(key: "first")).count
  end

  test "final_form granted when a monster reaches stage 3" do
    species3 = MonsterSpecies.create!(key: "bg_pup_3", stage: 3, dex_no: 1)
    @user.user_monsters.create!(monster_species: species3, dex_no: 1, obtained_at: Time.current)
    @user.refresh_badges!
    assert_includes keys, "final_form"
  end

  # DENOMINATOR FIXED AT 24 — owning all 12 seeded lines must NOT complete the dex.
  test "dex_half granted at 12 owned lines but dex_complete is NOT (denominator 24)" do
    seed_monster_species!
    MonsterSpecies.where(stage: 1).find_each do |species|
      @user.user_monsters.create!(monster_species: species, dex_no: species.dex_no, obtained_at: Time.current)
    end
    assert_equal 12, @user.user_monsters.distinct.count(:dex_no)

    @user.refresh_badges!
    assert_includes keys, "dex_half", "12 >= 12 lines should grant dex_half"
    assert_not_includes keys, "dex_complete", "12 of 24 must not complete the dex"
  end

  test "dex_half NOT granted below 12 owned lines" do
    seed_monster_species!
    MonsterSpecies.where(stage: 1).limit(11).each do |species|
      @user.user_monsters.create!(monster_species: species, dex_no: species.dex_no, obtained_at: Time.current)
    end
    @user.refresh_badges!
    assert_not_includes keys, "dex_half"
  end
end
