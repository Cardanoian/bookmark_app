require "test_helper"

# 미션 재설계(menu_refactor 심화 §2.A·§6.1) 모델 검증·상태 파생 커버리지.
class MissionTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "미션초등학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @teacher = User.create!(school: @school, classroom: @classroom, name: "김담임",
                            email: "mission_teacher@example.com", password: "password", role: :teacher)
  end

  def valid_attrs(overrides = {})
    { classroom: @classroom, title: "7월 독서왕", created_by: @teacher,
      start_date: Date.current, end_date: Date.current + 10 }.merge(overrides)
  end

  # 목표 1개를 붙여 발행 상태로 만든 미션(발행 검증 통과용).
  def published_mission(overrides = {})
    mission = Mission.new(valid_attrs(overrides))
    mission.mission_goals.build(goal_type: :approved_reports, target_count: 1)
    mission.status = :published
    mission.save!
    mission
  end

  test "유효한 미션은 저장된다(기본 draft)" do
    mission = Mission.new(valid_attrs)
    assert mission.valid?, mission.errors.full_messages.to_sentence
    assert mission.draft?
    assert_equal 0, mission.reward_points
  end

  test "title 은 필수이며 1..80 자" do
    assert Mission.new(valid_attrs(title: nil)).invalid?
    assert Mission.new(valid_attrs(title: "")).invalid?
    assert Mission.new(valid_attrs(title: "가" * 81)).invalid?
    assert Mission.new(valid_attrs(title: "가" * 80)).valid?
  end

  test "start_date·end_date 는 필수" do
    assert Mission.new(valid_attrs(start_date: nil)).invalid?
    assert Mission.new(valid_attrs(end_date: nil)).invalid?
  end

  test "end_date 가 start_date 보다 빠르면 무효" do
    mission = Mission.new(valid_attrs(start_date: Date.current, end_date: Date.current - 1))
    assert mission.invalid?
    assert_includes mission.errors[:end_date], "은 시작일보다 빠를 수 없습니다"
  end

  test "reward_points 는 0 이상 상한(기본 200) 이하" do
    assert Mission.new(valid_attrs(reward_points: -1)).invalid?
    assert Mission.new(valid_attrs(reward_points: 0)).valid?
    assert Mission.new(valid_attrs(reward_points: 200)).valid?
    assert Mission.new(valid_attrs(reward_points: 201)).invalid?
  end

  test "reward_max_points 는 AppSetting 값을 쓰되 무효 시 200 폴백" do
    assert_equal 200, Mission.reward_max_points
    AppSetting.set("mission_reward_max_points", 300)
    assert_equal 300, Mission.reward_max_points
    assert Mission.new(valid_attrs(reward_points: 300)).valid?
  ensure
    AppSetting.set("mission_reward_max_points", nil)
  end

  test "발행하려면 목표가 1개 이상 있어야 한다" do
    mission = Mission.create!(valid_attrs)
    mission.status = :published
    assert mission.invalid?
    assert_includes mission.errors[:base], "발행하려면 목표를 1개 이상 추가하세요"

    mission.mission_goals.build(goal_type: :approved_reports, target_count: 3)
    assert mission.valid?, mission.errors.full_messages.to_sentence
  end

  test "status enum 매핑" do
    assert_equal({ "draft" => 0, "published" => 1, "cancelled" => 2, "archived" => 3 }, Mission.statuses)
  end

  test "scheduled? 는 발행 + 오늘 < 시작일" do
    mission = published_mission(start_date: Date.current + 2, end_date: Date.current + 5)
    assert mission.scheduled?
    assert_not mission.active?
    assert_not mission.ended?
  end

  test "active? 는 발행 + 시작일 <= 오늘 <= 종료일" do
    mission = published_mission(start_date: Date.current - 1, end_date: Date.current + 1)
    assert mission.active?
    assert_not mission.scheduled?
    assert_not mission.ended?
  end

  test "ended? 는 발행 + 오늘 > 종료일" do
    mission = published_mission(start_date: Date.current - 5, end_date: Date.current - 1)
    assert mission.ended?
    assert_not mission.active?
    assert_not mission.scheduled?
  end

  test "draft 미션은 어떤 날짜 상태도 아니다" do
    draft = Mission.create!(valid_attrs)
    assert_not draft.scheduled?
    assert_not draft.active?
    assert_not draft.ended?
  end

  test "mission_goals·mission_participations 를 파괴 종속으로 거느린다" do
    mission = Mission.create!(valid_attrs)
    mission.mission_goals.create!(goal_type: :approved_reports, target_count: 2)
    student = User.create!(school: @school, classroom: @classroom, name: "학생", password: "password")
    mission.mission_participations.create!(user: student)

    assert_difference [ "MissionGoal.count", "MissionParticipation.count" ], -1 do
      mission.destroy
    end
  end
end
