# 문항 채점타입 5종 표현(Phase 1 §1.1). 기존 choices/answer_index 는 mcq_single
# 하위호환으로 남기고, 다형 문항(mcq_multi/matching/hint_reveal)을 위해
# content(문항 데이터)/answer(정답 표현)/explanation/difficulty/source(출처)를 추가한다.
class AddContentTypeToQuizQuestions < ActiveRecord::Migration[8.1]
  def change
    add_column :quiz_questions, :question_type, :integer, default: 0, null: false
    add_column :quiz_questions, :content, :json
    add_column :quiz_questions, :answer, :json
    add_column :quiz_questions, :explanation, :text
    add_column :quiz_questions, :difficulty, :integer
    add_column :quiz_questions, :source, :integer, default: 0, null: false
  end
end
