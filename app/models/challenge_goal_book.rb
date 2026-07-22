# 챌린지 목표의 지정 도서 허용목록 조인(MissionGoalBook 미러, '여러 책' any-of). 목록 중 어느 책
# 활동이든 목표에 합산(Challenges::ProgressCalculator 가 book_ids IN 으로 필터). 목표·도서 삭제 시 정리.
class ChallengeGoalBook < ApplicationRecord
  belongs_to :challenge_goal
  belongs_to :book

  validates :book_id, uniqueness: { scope: :challenge_goal_id }
end
