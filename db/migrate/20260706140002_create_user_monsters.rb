class CreateUserMonsters < ActiveRecord::Migration[8.1]
  def change
    create_table :user_monsters do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :dex_no
      t.references :monster_species, null: false, foreign_key: true
      t.string :nickname
      t.datetime :obtained_at
      t.datetime :evolved_at
      t.json :care

      t.timestamps
    end

    add_index :user_monsters, :dex_no
    add_index :user_monsters, [ :user_id, :dex_no ], unique: true
  end
end
