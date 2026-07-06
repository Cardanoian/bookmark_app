# 문장 스티커 동료평가(P5.3). report 본문 위치(position)에 이모지/라벨을 붙인다.
class CreateStickers < ActiveRecord::Migration[8.1]
  def change
    create_table :stickers do |t|
      t.references :report, null: false, foreign_key: true
      t.integer :position
      t.string :emoji
      t.string :label
      t.references :by_user, null: false, foreign_key: { to_table: :users }

      t.timestamps
    end
  end
end
