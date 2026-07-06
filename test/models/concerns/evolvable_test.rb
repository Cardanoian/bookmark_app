require "test_helper"

class EvolvableTest < ActiveSupport::TestCase
  setup do
    seed_monster_species!
    seed_badges!
    @school = School.create!(name: "진화초등학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @user = User.create!(school: @school, classroom: @classroom, name: "진화학생", password: "password")
    @monster = MonsterAcquisition.new(@user).choose_starter!("pup_1")
  end

  def add_reviewed_reports(count)
    count.times { |i| Report.create!(user: @user, classroom: @classroom, book_title: "책#{i}", reviewed: true) }
  end

  test "starter is not evolvable before conditions are met" do
    assert_not @monster.evolvable?
    assert_not @user.check_evolution!
    assert_empty @user.evolvable_monsters
  end

  test "starter becomes evolvable once pup_1 condition (points 100 + reports 3) is met" do
    @user.update!(points: 100)
    add_reviewed_reports(3)

    assert @monster.reload.evolvable?
    assert @user.check_evolution!
    assert_includes @user.evolvable_monsters, @monster
  end

  test "not evolvable when only points threshold is met (behavior condition unmet)" do
    @user.update!(points: 100)
    add_reviewed_reports(2)
    assert_not @monster.reload.evolvable?
  end

  test "evolve_active_monster! advances species in place and stamps evolved_at" do
    @user.update!(points: 100)
    add_reviewed_reports(3)

    new_form = @user.evolve_active_monster!

    assert_equal "pup_2", new_form.key
    @monster.reload
    assert_equal "pup_2", @monster.monster_species.key
    assert_equal 1, @monster.dex_no, "evolution is in-place (same dex line)"
    assert @monster.evolved_at.present?
  end

  test "evolve_active_monster! returns nil when conditions are not met" do
    assert_nil @user.evolve_active_monster!
    assert_equal "pup_1", @monster.reload.monster_species.key
  end

  test "fully evolved (stage 3) monster is not evolvable" do
    stage3 = MonsterSpecies.find_by(key: "pup_3")
    @monster.update!(monster_species: stage3)
    @user.update!(points: 5000)
    assert_not @monster.reload.evolvable?
  end

  test "evolving grants first_evolve badge" do
    @user.update!(points: 100)
    add_reviewed_reports(3)
    @user.evolve_active_monster!
    assert_includes @user.badges.reload.pluck(:key), "first_evolve"
  end
end
