class CreateSchools < ActiveRecord::Migration[8.1]
  def change
    create_table :schools do |t|
      t.string :neis_code
      t.string :name
      t.string :region
      t.string :gu
      t.string :office_code

      t.timestamps
    end

    add_index :schools, :neis_code, unique: true
    add_index :schools, :name
  end
end
