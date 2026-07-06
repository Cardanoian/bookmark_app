class CreatePurchases < ActiveRecord::Migration[8.1]
  def change
    create_table :purchases do |t|
      t.references :user, null: false, foreign_key: true
      t.references :shop_item, null: false, foreign_key: true
      t.integer :quantity, default: 1, null: false
      t.datetime :bought_at

      t.timestamps
    end

    add_index :purchases, [ :user_id, :shop_item_id ], unique: true
  end
end
