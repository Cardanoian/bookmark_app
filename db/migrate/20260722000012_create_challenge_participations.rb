# 학생별 챌린지 참여·완료·보상 원장(챌린지 목표화 — mission_participations 미러). 챌린지당 학생 1행
# (유니크 [challenge_id, user_id]). completed_at 이 완료, rewarded_at + reward_points_awarded 가
# 정확히-1회 보상 원장이다(Challenges::Rewarder 가 조건부 UPDATE 로 선점). reward_points_awarded 는
# 음수 불가(CHECK). 미션과 달리 assigned/unassigned 기간이 없다 — 챌린지는 전국/학교 스코프라
# 발행 시 학생 전원에게 eager 배정하지 않고, 활동 트리거·상세 조회 시 **지연(lazy) 생성**한다.
class CreateChallengeParticipations < ActiveRecord::Migration[8.1]
  def change
    create_table :challenge_participations do |t|
      t.references :challenge, null: false, foreign_key: true
      t.references :user,      null: false, foreign_key: true
      t.datetime :completed_at
      t.datetime :rewarded_at
      t.integer :reward_points_awarded, null: false, default: 0

      t.timestamps

      t.check_constraint "reward_points_awarded >= 0", name: "chk_challenge_participations_reward_nonneg"
    end

    # 챌린지당 학생 1행(중복 참여 방지 + 지연 생성 동시성 백스톱).
    add_index :challenge_participations, [ :challenge_id, :user_id ], unique: true
  end
end
