# 독서 퀴즈(P5.6). book/classroom 은 nullable(전역·총괄 퀴즈 허용), created_by 는 출제자(교사/총괄).
class CreateQuizzes < ActiveRecord::Migration[8.1]
  def change
    create_table :quizzes do |t|
      t.integer :book_id
      t.integer :classroom_id
      t.integer :created_by_id, null: false
      t.string :title
      t.integer :scope, null: false, default: 0
      t.boolean :published, null: false, default: false

      t.timestamps
    end

    add_index :quizzes, :book_id
    add_index :quizzes, :classroom_id
    add_index :quizzes, :created_by_id
    add_foreign_key :quizzes, :users, column: :created_by_id
  end
end
