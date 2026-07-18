require "test_helper"

# 미션 목표(menu_refactor 심화 §2.A.5·§6.1) — enum·유니크·target_count 검증/CHECK.
class MissionGoalTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "목표초등학교")
    @classroom = Classroom.create!(school: @school, grade: 4, class_no: 2)
    @mission = Mission.create!(classroom: @classroom, title: "목표 미션",
                               start_date: Date.current, end_date: Date.current + 7)
  end

  test "goal_type enum 매핑" do
    assert_equal({ "approved_reports" => 0, "game_plays" => 1 }, MissionGoal.goal_types)
  end

  test "유효한 목표는 저장된다" do
    goal = MissionGoal.new(mission: @mission, goal_type: :approved_reports, target_count: 3)
    assert goal.valid?, goal.errors.full_messages.to_sentence
  end

  test "target_count 는 1 이상(모델 검증)" do
    assert MissionGoal.new(mission: @mission, goal_type: :approved_reports, target_count: 0).invalid?
    assert MissionGoal.new(mission: @mission, goal_type: :approved_reports, target_count: -1).invalid?
    assert MissionGoal.new(mission: @mission, goal_type: :approved_reports, target_count: 1).valid?
  end

  test "target_count <= 0 은 DB CHECK 제약으로도 거부(검증 우회 시)" do
    goal = MissionGoal.new(mission: @mission, goal_type: :game_plays, target_count: 0)
    assert_raises(ActiveRecord::StatementInvalid) do
      goal.save!(validate: false)
    end
  end

  test "goal_type 은 미션 안에서 유일(모델 검증)" do
    MissionGoal.create!(mission: @mission, goal_type: :approved_reports, target_count: 2)
    dup = MissionGoal.new(mission: @mission, goal_type: :approved_reports, target_count: 5)
    assert dup.invalid?
    assert_includes dup.errors[:goal_type], I18n.t("errors.messages.taken")
  end

  test "goal_type 유일성은 DB 유니크 인덱스로도 보증(검증 우회 시)" do
    MissionGoal.create!(mission: @mission, goal_type: :approved_reports, target_count: 2)
    dup = MissionGoal.new(mission: @mission, goal_type: :approved_reports, target_count: 5)
    assert_raises(ActiveRecord::RecordNotUnique) do
      dup.save!(validate: false)
    end
  end

  test "서로 다른 goal_type 은 같은 미션에 공존한다" do
    MissionGoal.create!(mission: @mission, goal_type: :approved_reports, target_count: 2)
    other = MissionGoal.new(mission: @mission, goal_type: :game_plays, target_count: 3)
    assert other.valid?
    assert_nothing_raised { other.save! }
  end
end
