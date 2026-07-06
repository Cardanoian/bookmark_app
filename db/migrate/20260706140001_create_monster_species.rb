class CreateMonsterSpecies < ActiveRecord::Migration[8.1]
  def change
    create_table :monster_species do |t|
      t.integer :dex_no
      t.integer :stage
      t.string :key
      t.string :name
      t.integer :element, default: 0
      t.integer :rarity, default: 0
      t.references :evolves_from, foreign_key: { to_table: :monster_species }
      t.json :evolve_condition
      t.string :image_key
      t.text :description

      t.timestamps
    end

    add_index :monster_species, :dex_no
    add_index :monster_species, :key, unique: true
  end
end
