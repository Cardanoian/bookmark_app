require "test_helper"
require "rake"

# challenges:seed 스모크. db/seeds/challenges.yml 을 읽어 전국/학교 챌린지와 목표를 멱등 적재하고,
# 학교 스코프는 neis_code 로 실학교를 찾는다(없으면 그 챌린지만 건너뜀). 참여 행은 만들지 않는다.
class ChallengesSeedTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("challenges:seed")
    Challenge.delete_all
  end

  def run_task
    Rake::Task["challenges:seed"].reenable
    capture_io { Rake::Task["challenges:seed"].invoke }.first
  end

  test "전국·학교 챌린지를 목표와 함께 만들고 재실행해도 늘지 않는다" do
    School.find_or_create_by!(neis_code: "9999999") { |s| s.name = "테스트초등학교" }

    run_task
    created = Challenge.count
    goals = ChallengeGoal.count
    assert_operator created, :>=, 2

    global = Challenge.find_by(scope: :global)
    assert_not_nil global, "전국 챌린지가 있어야 한다"
    assert_nil global.school_id
    assert_equal 2, global.challenge_goals.count
    assert global.active?, "시드 챌린지는 오늘 기준 활성이어야 한다"

    school = Challenge.find_by(scope: :school)
    assert_not_nil school, "학교 챌린지가 있어야 한다"
    assert_equal "9999999", school.school.neis_code
    assert_operator school.reward_points, :<=, Challenge.reward_max_points

    # 목표는 종류당 1개(유니크 [challenge_id, goal_type])이고 target 은 1 이상.
    Challenge.find_each do |challenge|
      types = challenge.challenge_goals.map(&:goal_type)
      assert_equal types.uniq.size, types.size
      challenge.challenge_goals.each { |goal| assert_operator goal.target_count, :>, 0 }
    end

    # 참여·보상은 EvaluateProgress 가 지연 생성한다 — 시드는 만들지 않는다.
    assert_equal 0, ChallengeParticipation.count

    run_task
    assert_equal created, Challenge.count, "재실행은 챌린지를 늘리지 않는다"
    assert_equal goals, ChallengeGoal.count, "재실행은 목표를 늘리지 않는다"
  end

  test "학교를 찾을 수 없으면 그 챌린지만 건너뛰고 전국 챌린지는 만든다" do
    School.where(neis_code: "9999999").destroy_all

    out = run_task

    assert_match "건너뜀", out
    assert_not_nil Challenge.find_by(scope: :global)
    assert_nil Challenge.find_by(scope: :school)
  end
end
