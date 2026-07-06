class AddActiveMonsterForeignKeyToUsers < ActiveRecord::Migration[8.1]
  def change
    add_foreign_key :users, :user_monsters, column: :active_monster_id
  end
end
