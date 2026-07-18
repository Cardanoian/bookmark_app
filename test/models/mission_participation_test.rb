require "test_helper"

# 미션 참여 원장(menu_refactor 심화 §2.A.5·§6.1) — 유니크·reward_points_awarded 검증/CHECK.
# 클래스명은 기존 integration/mission_participation_test.rb(구 세션 참여 흐름, ActionDispatch::IntegrationTest)의
# MissionParticipationTest 와 충돌(superclass mismatch)을 피하려 ...ModelTest 로 둔다.
class MissionParticipationModelTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "참여초등학교")
    @classroom = Classroom.create!(school: @school, grade: 6, class_no: 1)
    @mission = Mission.create!(classroom: @classroom, title: "참여 미션",
                               start_date: Date.current, end_date: Date.current + 7)
    @student = User.create!(school: @school, classroom: @classroom, name: "참여학생", password: "password")
  end

  test "유효한 참여는 저장된다(reward_points_awarded 기본 0)" do
    participation = MissionParticipation.new(mission: @mission, user: @student)
    assert participation.valid?, participation.errors.full_messages.to_sentence
    participation.save!
    assert_equal 0, participation.reward_points_awarded
  end

  test "미션당 학생 1행(모델 검증)" do
    MissionParticipation.create!(mission: @mission, user: @student)
    dup = MissionParticipation.new(mission: @mission, user: @student)
    assert dup.invalid?
    assert_includes dup.errors[:user_id], I18n.t("errors.messages.taken")
  end

  test "미션당 학생 1행은 DB 유니크 인덱스로도 보증(검증 우회 시)" do
    MissionParticipation.create!(mission: @mission, user: @student)
    dup = MissionParticipation.new(mission: @mission, user: @student)
    assert_raises(ActiveRecord::RecordNotUnique) do
      dup.save!(validate: false)
    end
  end

  test "reward_points_awarded 는 음수 불가(모델 검증)" do
    assert MissionParticipation.new(mission: @mission, user: @student, reward_points_awarded: -1).invalid?
    assert MissionParticipation.new(mission: @mission, user: @student, reward_points_awarded: 0).valid?
    assert MissionParticipation.new(mission: @mission, user: @student, reward_points_awarded: 100).valid?
  end

  test "reward_points_awarded 음수는 DB CHECK 제약으로도 거부(검증 우회 시)" do
    participation = MissionParticipation.new(mission: @mission, user: @student, reward_points_awarded: -5)
    assert_raises(ActiveRecord::StatementInvalid) do
      participation.save!(validate: false)
    end
  end

  test "mission·user 연관" do
    participation = MissionParticipation.create!(mission: @mission, user: @student)
    assert_equal @mission, participation.mission
    assert_equal @student, participation.user
    assert_includes @student.mission_participations, participation
  end
end
