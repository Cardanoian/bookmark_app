class CreateBadges < ActiveRecord::Migration[8.1]
  def change
    create_table :badges do |t|
      t.string :key
      t.string :name
      t.string :icon
      t.string :condition_desc

      t.timestamps
    end

    add_index :badges, :key, unique: true
  end
end
