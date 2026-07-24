# 랭킹 시즌제 점수(account_linking_seasons_plan §Phase 0). 학년도(academic_year)별 학생 1행으로,
# 그 학년도에 적립한 경험치(experience_earned)·포인트(points_earned)만 담는다. 평생 카운터
# (users.experience/points)와 분리돼 매 학년도 0에서 재출발하며 랭킹의 단일 진실이 된다.
# 증감은 Pointable 의 raw upsert(ON CONFLICT) 로만 이뤄지고, 스냅샷 3컬럼(school_id/classroom_id/grade)은
# 감사·과거 시즌 재현 전용이라 랭킹 그룹핑에는 쓰지 않는다.
class SeasonScore < ApplicationRecord
  belongs_to :user

  validates :academic_year, :user_id, presence: true
  validates :experience_earned, numericality: { greater_than_or_equal_to: 0 }
  validates :points_earned, numericality: { greater_than_or_equal_to: 0 }

  scope :for_year, ->(year) { where(academic_year: year) }
end
