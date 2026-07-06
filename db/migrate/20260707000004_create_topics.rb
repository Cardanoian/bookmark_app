# 토론방(P5.4). scope=classroom/school 로 학급·학교 단위 토론을 구분한다.
class CreateTopics < ActiveRecord::Migration[8.1]
  def change
    create_table :topics do |t|
      t.integer :scope, null: false, default: 0
      t.integer :classroom_id
      t.integer :school_id
      t.integer :book_id
      t.string :title
      t.boolean :hidden, null: false, default: false

      t.timestamps
    end

    add_index :topics, :classroom_id
    add_index :topics, :school_id
  end
end
