class CreateClassrooms < ActiveRecord::Migration[8.1]
  def change
    create_table :classrooms do |t|
      t.references :school, null: false, foreign_key: true
      t.integer :grade
      t.integer :class_no
      t.references :teacher, foreign_key: { to_table: :users }
      t.json :rubric_config

      t.timestamps
    end

    add_index :classrooms, [ :school_id, :grade, :class_no ], unique: true
  end
end
