# 퀴즈 플레이 기록(P5.6). 게임 결과 → 포인트 반영(ReadingStats.quizzes 집계 대상).
class CreateQuizAttempts < ActiveRecord::Migration[8.1]
  def change
    create_table :quiz_attempts do |t|
      t.integer :quiz_id, null: false
      t.integer :user_id, null: false
      t.integer :score
      t.json :answers
      t.datetime :played_at

      t.timestamps
    end

    add_index :quiz_attempts, :quiz_id
    add_index :quiz_attempts, :user_id
    add_foreign_key :quiz_attempts, :quizzes
    add_foreign_key :quiz_attempts, :users
  end
end
