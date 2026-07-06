# 우수작 게시판 게시물(P5.3). report 1개당 게시물 1개(unique). hidden 은 모더레이션용.
class CreateBoardPosts < ActiveRecord::Migration[8.1]
  def change
    create_table :board_posts do |t|
      t.references :report, null: false, foreign_key: true, index: { unique: true }
      t.boolean :hidden, null: false, default: false
      t.references :hidden_by, foreign_key: { to_table: :users }

      t.timestamps
    end
  end
end
