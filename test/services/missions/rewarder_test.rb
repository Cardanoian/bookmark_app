require "test_helper"

# 미션 보상 지급(menu_refactor 심화 §2.A.1·§6.1) — 정확히-1회·멱등·m6 가드·0P 완료.
class Missions::RewarderTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "보상초")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @student = User.create!(school: @school, classroom: @classroom, name: "보상생", password: "password", points: 0)
  end

  def mission_with(goal_target: 1, reward_points: 50, published: true)
    mission = Mission.new(classroom: @classroom, title: "보상미션", reward_points: reward_points,
                          start_date: Date.current - 1, end_date: Date.current + 5)
    mission.mission_goals.build(goal_type: :approved_reports, target_count: goal_target)
    mission.status = published ? :published : :draft
    mission.save!(validate: published) # draft 는 목표 없이도 저장되게 검증 우회 불요(목표 있음)
    mission
  end

  def approved_report
    Report.create!(user: @student, classroom: @classroom, book_title: "책", reviewed: true, created_at: Time.current)
  end

  test "목표 미충족이면 지급하지 않는다(nil)" do
    mission = mission_with(goal_target: 2)
    approved_report # 1편만(목표 2)
    part = MissionParticipation.create!(mission: mission, user: @student)
    assert_nil Missions::Rewarder.new.reward!(part)
    assert_equal 0, @student.reload.points
    assert_nil part.reload.rewarded_at
  end

  test "완료 시 정확한 포인트를 1회 지급하고 원장을 기록한다" do
    mission = mission_with(reward_points: 70)
    approved_report
    part = MissionParticipation.create!(mission: mission, user: @student)
    result = Missions::Rewarder.new.reward!(part)
    assert_equal part, result
    part.reload
    assert part.completed_at.present?
    assert part.rewarded_at.present?
    assert_equal 70, part.reward_points_awarded
    assert_equal 70, @student.reload.points
  end

  test "반복 호출해도 추가 지급이 없다(멱등)" do
    mission = mission_with(reward_points: 40)
    approved_report
    part = MissionParticipation.create!(mission: mission, user: @student)
    3.times { Missions::Rewarder.new.reward!(part) }
    assert_equal 40, @student.reload.points
    assert_equal 40, part.reload.reward_points_awarded
  end

  test "m6: 목표가 없는 미션은 지급하지 않는다(vacuous-true 오지급 방지)" do
    mission = Mission.new(classroom: @classroom, title: "무목표", reward_points: 50,
                          start_date: Date.current - 1, end_date: Date.current + 5, status: :published)
    mission.save!(validate: false)  # 목표 0 + published 강제
    part = MissionParticipation.create!(mission: mission, user: @student)
    assert_nil Missions::Rewarder.new.reward!(part)
    assert_equal 0, @student.reload.points
  end

  test "m6: 미발행(draft/archived) 미션은 지급하지 않는다" do
    mission = mission_with(reward_points: 50, published: false)  # draft
    approved_report
    part = MissionParticipation.create!(mission: mission, user: @student)
    assert_nil Missions::Rewarder.new.reward!(part)
    assert_equal 0, @student.reload.points
  end

  test "0P 미션은 포인트 없이 완료·보상 처리(완료 표시)" do
    mission = mission_with(reward_points: 0)
    approved_report
    part = MissionParticipation.create!(mission: mission, user: @student)
    Missions::Rewarder.new.reward!(part)
    part.reload
    assert part.completed_at.present?
    assert part.rewarded_at.present?
    assert_equal 0, part.reward_points_awarded
    assert_equal 0, @student.reload.points
  end
end
