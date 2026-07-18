require "test_helper"

# 학생 미션 자동 배정(menu_refactor 심화 §2.A.6·§6.2) — 발행 시 전원 배정·멱등·편입 즉시 배정+평가.
class Missions::AssignmentSyncTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "배정초")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @teacher = User.create!(school: @school, classroom: @classroom, name: "배정샘", email: "assign_t@example.com", password: "password", role: :teacher)
    @classroom.update!(teacher: @teacher)
    @s1 = User.create!(school: @school, classroom: @classroom, name: "학생1", password: "password")
    @s2 = User.create!(school: @school, classroom: @classroom, name: "학생2", password: "password")
  end

  def published_mission(reward_points: 30)
    mission = Mission.new(classroom: @classroom, title: "배정미션", reward_points: reward_points,
                          start_date: Date.current - 1, end_date: Date.current + 5)
    mission.mission_goals.build(goal_type: :approved_reports, target_count: 1)
    mission.status = :published
    mission.save!
    mission
  end

  test "on_publish 는 학급 학생 전원에 participation 을 배정한다(교사 제외)" do
    mission = published_mission
    Missions::AssignmentSync.on_publish(mission)
    assert MissionParticipation.exists?(mission: mission, user: @s1)
    assert MissionParticipation.exists?(mission: mission, user: @s2)
    assert_not MissionParticipation.exists?(mission: mission, user: @teacher)
  end

  test "on_publish 는 멱등(반복 호출에도 중복 행 없음)" do
    mission = published_mission
    Missions::AssignmentSync.on_publish(mission)
    assert_no_difference -> { MissionParticipation.count } do
      Missions::AssignmentSync.on_publish(mission)
    end
  end

  test "on_publish 는 발행 시점 이전 창 내 활동을 즉시 평가로 반영한다(지연배정 갭)" do
    # 학생이 이미 승인 독후감을 쓴 뒤 미션이 발행되는 경우
    Report.create!(user: @s1, classroom: @classroom, book_title: "책", reviewed: true, created_at: Time.current)
    mission = published_mission(reward_points: 25)
    Missions::AssignmentSync.on_publish(mission)
    part = MissionParticipation.find_by(mission: mission, user: @s1)
    assert part.completed_at.present?, "발행 즉시 평가로 완료돼야 한다"
    assert_equal 25, @s1.reload.points
  end

  test "for_user 는 편입 학생을 현재 학급의 진행 중 미션에 배정하고 즉시 평가한다" do
    mission = published_mission(reward_points: 15)
    Missions::AssignmentSync.on_publish(mission)  # 기존 학생 배정
    # 신규 편입 학생 + 편입 前 활동
    newbie = User.create!(school: @school, classroom: @classroom, name: "편입생", password: "password")
    Report.create!(user: newbie, classroom: @classroom, book_title: "책", reviewed: true, created_at: Time.current)

    Missions::AssignmentSync.for_user(newbie)
    part = MissionParticipation.find_by(mission: mission, user: newbie)
    assert part.present?, "편입 학생이 배정돼야 한다"
    assert part.completed_at.present?, "편입 즉시 평가로 완료돼야 한다"
    assert_equal 15, newbie.reload.points
  end

  test "ReevaluateJob 백스톱도 미보상 완료를 지급한다(멱등)" do
    mission = published_mission(reward_points: 20)
    Missions::AssignmentSync.on_publish(mission)
    # 배정 후 활동(트리거를 일부러 태우지 않음 → 잡이 흡수)
    Report.create!(user: @s1, classroom: @classroom, book_title: "책", reviewed: true, created_at: Time.current)
    assert_equal 0, @s1.reload.points

    Missions::ReevaluateJob.new.perform
    assert_equal 20, @s1.reload.points
    # 재실행 멱등
    Missions::ReevaluateJob.new.perform
    assert_equal 20, @s1.reload.points
  end
end
