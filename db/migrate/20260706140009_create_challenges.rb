class CreateChallenges < ActiveRecord::Migration[8.1]
  def change
    create_table :challenges do |t|
      t.integer :scope, default: 0
      t.integer :school_id
      t.integer :book_id
      t.string :title
      t.date :starts_on
      t.date :ends_on

      t.timestamps
    end

    add_index :challenges, :school_id
  end
end
