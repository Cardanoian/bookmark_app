# 퀴즈 문항(P5.6). choices 는 보기 배열(json), answer_index 는 정답 보기 인덱스.
class CreateQuizQuestions < ActiveRecord::Migration[8.1]
  def change
    create_table :quiz_questions do |t|
      t.integer :quiz_id, null: false
      t.text :prompt
      t.json :choices
      t.integer :answer_index
      t.integer :position

      t.timestamps
    end

    add_index :quiz_questions, :quiz_id
    add_foreign_key :quiz_questions, :quizzes
  end
end
