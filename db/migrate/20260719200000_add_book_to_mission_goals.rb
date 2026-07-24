# 미션 목표에 특정 도서 지정(선택) 컬럼 추가. book_id 가 있으면 그 책의 독후감/게임만 인정하고,
# nil 이면 아무 책의 독서활동으로도 목표를 채울 수 있다(기존 동작). 도서 삭제 시 참조만 끊는다
# (reports.book_id·monster 자기참조와 동일한 on_delete: :nullify 정합).
class AddBookToMissionGoals < ActiveRecord::Migration[8.1]
  def change
    add_reference :mission_goals, :book, null: true, foreign_key: { on_delete: :nullify }
  end
end
