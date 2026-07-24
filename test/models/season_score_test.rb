require "test_helper"

# 랭킹 시즌제 점수 모델(account_linking_seasons_plan §Phase 0) — 검증·[academic_year,user_id] 유니크·음수 거부.
class SeasonScoreTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "시즌초등학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @user = User.create!(school: @school, classroom: @classroom, name: "시즌학생", password: "password")
  end

  test "valid with required attributes" do
    score = SeasonScore.new(user: @user, academic_year: 2026, experience_earned: 10, points_earned: 5)
    assert score.valid?
  end

  test "requires academic_year" do
    score = SeasonScore.new(user: @user)
    assert_not score.valid?
    assert_includes score.errors.attribute_names, :academic_year
  end

  test "requires a user" do
    score = SeasonScore.new(academic_year: 2026)
    assert_not score.valid?
    assert_includes score.errors.attribute_names, :user
  end

  test "rejects negative experience_earned" do
    score = SeasonScore.new(user: @user, academic_year: 2026, experience_earned: -1)
    assert_not score.valid?
    assert_includes score.errors.attribute_names, :experience_earned
  end

  test "rejects negative points_earned" do
    score = SeasonScore.new(user: @user, academic_year: 2026, points_earned: -5)
    assert_not score.valid?
    assert_includes score.errors.attribute_names, :points_earned
  end

  test "enforces uniqueness of [academic_year, user_id] at the database level" do
    SeasonScore.create!(user: @user, academic_year: 2026)

    dup = SeasonScore.new(user: @user, academic_year: 2026)
    assert_raises(ActiveRecord::RecordNotUnique) { dup.save(validate: false) }
  end

  test "same user may hold one row per academic year" do
    a = SeasonScore.create!(user: @user, academic_year: 2026, experience_earned: 3)
    b = SeasonScore.create!(user: @user, academic_year: 2027, experience_earned: 9)

    assert a.persisted?
    assert b.persisted?
  end

  test "for_year scopes to the given academic year" do
    this_year = SeasonScore.create!(user: @user, academic_year: 2026, experience_earned: 3)
    SeasonScore.create!(user: @user, academic_year: 2027, experience_earned: 9)

    assert_equal [ this_year ], SeasonScore.for_year(2026).to_a
  end
end
