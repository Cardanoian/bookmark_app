class CreateMissions < ActiveRecord::Migration[8.1]
  def change
    create_table :missions do |t|
      t.references :classroom, null: false, foreign_key: true
      t.integer :book_id
      t.string :title
      t.date :start_date
      t.date :end_date

      t.timestamps
    end

    add_index :missions, :book_id
  end
end
