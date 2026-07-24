# 응원(👏, P5.3). board_post + user 조합은 1인 1회(unique).
class CreateCheers < ActiveRecord::Migration[8.1]
  def change
    create_table :cheers do |t|
      t.references :board_post, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end

    add_index :cheers, [ :board_post_id, :user_id ], unique: true
  end
end
