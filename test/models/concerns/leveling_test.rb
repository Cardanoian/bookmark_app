require "test_helper"

class LevelingTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "레벨초등학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
  end

  def user_with(points)
    @seq = (@seq || 0) + 1
    User.create!(school: @school, classroom: @classroom, name: "레벨#{points}_#{@seq}", password: "password", points: points)
  end

  test "LEVEL_PATH and TRAINER_TITLES match §13.2" do
    assert_equal [ 0, 100, 250, 450, 700, 1000 ], Leveling::LEVEL_PATH
    assert_equal(
      [ "책읽기 새내기", "책벌레", "이야기 탐험가", "독서 모험가", "책갈피 지킴이", "책갈피 마스터" ],
      Leveling::TRAINER_TITLES
    )
  end

  test "level 1 at 0 and 99 points" do
    assert_equal 1, user_with(0).trainer_level
    assert_equal 1, user_with(99).trainer_level
    assert_equal "책읽기 새내기", user_with(0).trainer_title
  end

  test "level 2 at 100 points (boundary)" do
    assert_equal 2, user_with(100).trainer_level
    assert_equal "책벌레", user_with(100).trainer_title
  end

  test "each threshold bumps the level" do
    assert_equal 3, user_with(250).trainer_level
    assert_equal 4, user_with(450).trainer_level
    assert_equal 5, user_with(700).trainer_level
  end

  test "level 6 at 1000 points and above" do
    assert_equal 6, user_with(1000).trainer_level
    assert_equal 6, user_with(5000).trainer_level
    assert_equal "책갈피 마스터", user_with(1000).trainer_title
  end
end
