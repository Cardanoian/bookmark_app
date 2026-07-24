# 미션 목표의 '여러 책 허용목록'(단일 book_id → 다대다). 목표별로 여러 책을 지정하면 그 목록 중
# 어느 책 활동이든 목표에 합산하고(any-of), 목록이 비면 아무 책이나 인정한다. 단일 `book_id` 컬럼을
# `mission_goal_books` 조인으로 옮기고(기존 값 이관) book_id 컬럼은 제거한다.
class AddMultiBookToMissionGoals < ActiveRecord::Migration[8.1]
  def up
    create_table :mission_goal_books do |t|
      t.references :mission_goal, null: false, foreign_key: { on_delete: :cascade }
      t.references :book, null: false, foreign_key: { on_delete: :cascade }
      t.timestamps
    end
    add_index :mission_goal_books, [ :mission_goal_id, :book_id ], unique: true

    # 기존 단일 지정 도서를 조인으로 이관(book_id 있는 목표만).
    execute(<<~SQL.squish)
      INSERT INTO mission_goal_books (mission_goal_id, book_id, created_at, updated_at)
      SELECT id, book_id, datetime('now'), datetime('now') FROM mission_goals WHERE book_id IS NOT NULL
    SQL

    remove_reference :mission_goals, :book
  end

  def down
    add_reference :mission_goals, :book, null: true, foreign_key: { on_delete: :nullify }
    # 조인의 첫 책을 단일 book_id 로 되돌린다(왕복 손실은 목표당 2번째 이후 책뿐).
    execute(<<~SQL.squish)
      UPDATE mission_goals SET book_id =
        (SELECT book_id FROM mission_goal_books WHERE mission_goal_id = mission_goals.id ORDER BY id LIMIT 1)
    SQL
    drop_table :mission_goal_books
  end
end
