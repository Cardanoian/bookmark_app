class CreateReports < ActiveRecord::Migration[8.1]
  def change
    create_table :reports do |t|
      t.references :user, null: false, foreign_key: true
      t.references :classroom, null: false, foreign_key: true
      t.references :book, foreign_key: true
      t.string :book_title
      t.text :body
      t.integer :input_mode, default: 0, null: false
      t.json :rubric
      t.float :avg
      t.string :level, limit: 1
      t.json :teacher_rubric
      t.text :teacher_comment
      t.boolean :reviewed, default: false, null: false
      t.datetime :reviewed_at
      t.boolean :shared, default: false, null: false
      t.integer :cheers_count, default: 0, null: false
      t.integer :challenge_id
      t.integer :mission_id
      t.references :revision_of, foreign_key: { to_table: :reports }
      t.float :prev_avg
      t.float :improvement
      t.float :similarity
      t.integer :ai_status, default: 0, null: false

      t.timestamps
    end

    add_index :reports, :level
    add_index :reports, :reviewed
    add_index :reports, :challenge_id
    add_index :reports, :mission_id
    add_index :reports, [ :classroom_id, :reviewed ]
    add_index :reports, [ :user_id, :created_at ]
  end
end
