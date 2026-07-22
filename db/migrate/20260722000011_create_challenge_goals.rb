# 챌린지의 정량 목표(챌린지 목표화 — mission_goals 미러). 한 챌린지는 goal_type 당 최대 1개 목표를
# 가진다(유니크 [challenge_id, goal_type]). target_count 는 1 이상(CHECK). goal_type 정수 매핑은
# approved_reports=0, game_plays=1(ChallengeGoal enum·MissionGoal 과 정합).
# book_id 가 있으면 그 책의 독후감/게임만 인정하고, nil 이면 아무 책의 독서활동으로도 목표를 채운다
# (mission_goals 동일 동작). 도서 삭제 시 참조만 끊는다(on_delete: :nullify 정합).
class CreateChallengeGoals < ActiveRecord::Migration[8.1]
  def change
    create_table :challenge_goals do |t|
      t.references :challenge, null: false, foreign_key: true
      t.references :book, null: true, foreign_key: { on_delete: :nullify }
      t.integer :goal_type,    null: false
      t.integer :target_count, null: false
      t.integer :position

      t.timestamps

      t.check_constraint "target_count > 0", name: "chk_challenge_goals_target_count_positive"
    end

    # 목표 종류당 1개(중복 목표 방지).
    add_index :challenge_goals, [ :challenge_id, :goal_type ], unique: true
  end
end
