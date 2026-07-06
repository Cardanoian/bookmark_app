class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.integer :role, default: 0, null: false
      t.references :school, foreign_key: true
      t.integer :classroom_id
      t.string :name, null: false
      t.string :password_digest, null: false
      t.integer :points, default: 0, null: false
      t.integer :mode, default: 0, null: false
      t.integer :active_monster_id
      t.boolean :suspended, default: false, null: false

      t.timestamps
    end

    add_index :users, :role
    add_index :users, :classroom_id
    add_index :users, [ :school_id, :classroom_id, :name ],
              unique: true, name: "index_users_on_tuple_identity"
  end
end
