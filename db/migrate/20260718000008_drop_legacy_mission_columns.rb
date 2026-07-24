# 레거시 미션 컬럼 드롭(menu_refactor 심화 PR6, 파괴적 DDL·후행). 세션 참여방식 제거로
# reports.mission_id(참여 연결)는 더 이상 쓰지 않고(자동 배정·자동 진행으로 대체), missions.book_id
# (미션 지정 도서)도 새 목표 모델에서 제거한다(특정 도서 목표는 후속 goal_type). challenge 는 유지.
# remove_reference 는 FK·인덱스·컬럼을 함께 제거하고 change 로 가역(down 시 재생성).
class DropLegacyMissionColumns < ActiveRecord::Migration[8.1]
  def change
    remove_reference :reports, :mission, type: :integer, index: true, foreign_key: true
    remove_reference :missions, :book, type: :integer, index: true,
                     foreign_key: { to_table: :books, on_delete: :nullify }
  end
end
