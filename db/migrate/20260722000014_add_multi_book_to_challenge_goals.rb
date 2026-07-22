# 챌린지 목표의 '여러 책 허용목록'(mission_goals 미러). 단일 `book_id` 를 `challenge_goal_books`
# 조인으로 옮기고(기존 값 이관) book_id 컬럼을 제거한다. any-of: 목록 중 어느 책 활동이든 합산,
# 목록이 비면 아무 책이나 인정.
class AddMultiBookToChallengeGoals < ActiveRecord::Migration[8.1]
  def up
    create_table :challenge_goal_books do |t|
      t.references :challenge_goal, null: false, foreign_key: { on_delete: :cascade }
      t.references :book, null: false, foreign_key: { on_delete: :cascade }
      t.timestamps
    end
    add_index :challenge_goal_books, [ :challenge_goal_id, :book_id ], unique: true

    execute(<<~SQL.squish)
      INSERT INTO challenge_goal_books (challenge_goal_id, book_id, created_at, updated_at)
      SELECT id, book_id, datetime('now'), datetime('now') FROM challenge_goals WHERE book_id IS NOT NULL
    SQL

    remove_reference :challenge_goals, :book
  end

  def down
    add_reference :challenge_goals, :book, null: true, foreign_key: { on_delete: :nullify }
    execute(<<~SQL.squish)
      UPDATE challenge_goals SET book_id =
        (SELECT book_id FROM challenge_goal_books WHERE challenge_goal_id = challenge_goals.id ORDER BY id LIMIT 1)
    SQL
    drop_table :challenge_goal_books
  end
end
