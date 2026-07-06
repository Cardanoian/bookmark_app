class CreateShopItems < ActiveRecord::Migration[8.1]
  def change
    create_table :shop_items do |t|
      t.integer :category, default: 0
      t.string :name
      t.string :icon
      t.integer :cost, default: 0
      t.string :image_key
      t.json :effect
      t.boolean :consumable, default: false, null: false

      t.timestamps
    end
  end
end
