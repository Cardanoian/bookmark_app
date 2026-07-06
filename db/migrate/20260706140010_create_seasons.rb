class CreateSeasons < ActiveRecord::Migration[8.1]
  def change
    create_table :seasons do |t|
      t.integer :scope, default: 0
      t.integer :school_id
      t.string :name
      t.date :ends_on

      t.timestamps
    end
  end
end
