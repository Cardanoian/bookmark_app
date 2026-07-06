# 퀴즈 문항(P5.6). choices 보기 배열 + answer_index 정답 인덱스.
class QuizQuestion < ApplicationRecord
  belongs_to :quiz

  # 제출된 보기 인덱스가 정답과 일치하는지.
  def correct?(selected_index)
    !answer_index.nil? && selected_index.to_i == answer_index
  end

  # 안전한 보기 배열(nil → []).
  def choice_list
    Array(choices)
  end
end
