# 챌린지 완료 보상 포인트(챌린지 목표화 — 미션 미러). 모든 목표를 달성하면 정확히-1회 지급되는
# 포인트/경험치 양. 상한은 Challenge.reward_max_points(AppSetting "challenge_reward_max_points",
# 무효 시 기본값)로 서버가 재검증한다. 목표 없는 레거시 챌린지(join 방식)는 0 으로 남는다.
class AddRewardPointsToChallenges < ActiveRecord::Migration[8.1]
  def change
    add_column :challenges, :reward_points, :integer, null: false, default: 0
  end
end
