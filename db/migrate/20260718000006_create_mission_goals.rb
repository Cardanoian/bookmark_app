# 미션의 정량 목표(menu_refactor 심화 §2.A.5). 한 미션은 goal_type 당 최대 1개 목표를 가진다
# (유니크 [mission_id, goal_type]). target_count 는 1 이상(CHECK). goal_type 정수 매핑은
# approved_reports=0, game_plays=1(MissionGoal enum 과 정합).
class CreateMissionGoals < ActiveRecord::Migration[8.1]
  def change
    create_table :mission_goals do |t|
      t.references :mission, null: false, foreign_key: true
      t.integer :goal_type,    null: false
      t.integer :target_count, null: false
      t.integer :position

      t.timestamps

      t.check_constraint "target_count > 0", name: "chk_mission_goals_target_count_positive"
    end

    # 목표 종류당 1개(중복 목표 방지).
    add_index :mission_goals, [ :mission_id, :goal_type ], unique: true
  end
end
