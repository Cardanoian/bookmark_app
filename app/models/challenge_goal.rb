# 챌린지의 정량 목표(챌린지 목표화 — MissionGoal 미러). 한 챌린지는 goal_type 당 최대 1개 목표를
# 가진다(유니크 [challenge_id, goal_type]). target_count 는 1 이상(DB CHECK + 모델 검증).
# 특정 도서 지정(선택, '여러 책' any-of): challenge_goal_books 조인으로 여러 책을 걸 수 있고, 그 목록
# 중 어느 책 독후감/게임이든 목표에 합산한다(Challenges::ProgressCalculator 가 book_ids 로 필터). 비면 아무 책이나.
class ChallengeGoal < ApplicationRecord
  belongs_to :challenge

  has_many :challenge_goal_books, dependent: :destroy
  has_many :books, through: :challenge_goal_books

  enum :goal_type, { approved_reports: 0, game_plays: 1 }

  validates :goal_type, presence: true
  validates :goal_type, uniqueness: { scope: :challenge_id }
  validates :target_count, numericality: { only_integer: true, greater_than: 0 }
end
