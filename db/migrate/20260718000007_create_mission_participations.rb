# 학생별 미션 참여·완료·보상 원장(menu_refactor 심화 §2.A.5). 미션당 학생 1행(유니크
# [mission_id, user_id]). completed_at 이 완료(몬스터 지표 전환 후 단일 진실, PR2), rewarded_at +
# reward_points_awarded 가 정확히-1회 보상 원장이다(PR3 Rewarder 가 조건부 UPDATE 로 선점).
# reward_points_awarded 는 음수 불가(CHECK). [user_id, completed_at] 인덱스는 완료 미션 수 집계용.
class CreateMissionParticipations < ActiveRecord::Migration[8.1]
  def change
    create_table :mission_participations do |t|
      t.references :mission, null: false, foreign_key: true
      t.references :user,    null: false, foreign_key: true
      t.datetime :assigned_at
      t.datetime :unassigned_at
      t.datetime :completed_at
      t.datetime :rewarded_at
      t.integer :reward_points_awarded, null: false, default: 0

      t.timestamps

      t.check_constraint "reward_points_awarded >= 0", name: "chk_mission_participations_reward_nonneg"
    end

    # 미션당 학생 1행(중복 참여 방지 백스톱).
    add_index :mission_participations, [ :mission_id, :user_id ], unique: true
    # 완료 미션 수 집계(ReadingStats#missions PR2 전환) 지원.
    add_index :mission_participations, [ :user_id, :completed_at ]
  end
end
