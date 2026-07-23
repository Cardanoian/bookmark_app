class AddRankingPreferencesToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :nickname, :string
    add_column :users, :ranking_opted_in, :boolean, null: false, default: false

    add_index :users, [ :school_id, :nickname ],
              unique: true,
              where: "nickname IS NOT NULL",
              name: "index_users_on_school_and_nickname"
    add_index :users, [ :ranking_opted_in, :role ],
              name: "index_users_on_ranking_opt_in_and_role"
  end
end
