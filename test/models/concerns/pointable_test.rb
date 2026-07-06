require "test_helper"

class PointableTest < ActiveSupport::TestCase
  setup do
    seed_monster_species!
    seed_badges!
    @school = School.create!(name: "포인트초등학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @user = User.create!(school: @school, classroom: @classroom, name: "포인트학생", password: "password")
  end

  test "award_points increments and persists points" do
    @user.award_points(30)
    assert_equal 30, @user.reload.points
    @user.award_points(20)
    assert_equal 50, @user.reload.points
  end

  test "award_points ignores zero and negative amounts" do
    @user.award_points(0)
    @user.award_points(-10)
    assert_equal 0, @user.reload.points
  end

  test "award_points triggers badge refresh" do
    3.times { Report.create!(user: @user, classroom: @classroom, book_title: "책", reviewed: true) }
    @user.award_points(30)
    keys = @user.badges.reload.pluck(:key)
    assert_includes keys, "first"
    assert_includes keys, "three"
  end

  test "award_points triggers evolution check without auto-evolving" do
    MonsterAcquisition.new(@user).choose_starter!("pup_1")
    3.times { Report.create!(user: @user, classroom: @classroom, book_title: "책", reviewed: true) }

    # 99 -> still below threshold, not evolvable
    @user.award_points(99)
    assert_not @user.check_evolution!

    # crossing 100 makes it evolvable, but award_points must not auto-evolve
    @user.award_points(1)
    assert @user.check_evolution!
    assert_equal "pup_1", @user.active_monster.reload.monster_species.key
  end
end
