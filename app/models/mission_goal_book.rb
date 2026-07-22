# 미션 목표의 지정 도서 허용목록 조인('여러 책' any-of). 한 목표에 여러 책을 걸면 그 목록 중 어느
# 책 활동이든 목표에 합산한다(ProgressCalculator 가 book_ids IN 으로 필터). 목표·도서 삭제 시 함께 정리.
class MissionGoalBook < ApplicationRecord
  belongs_to :mission_goal
  belongs_to :book

  validates :book_id, uniqueness: { scope: :mission_goal_id }
end
