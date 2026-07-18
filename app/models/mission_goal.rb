# 미션의 정량 목표(menu_refactor 심화 §2.A.5). 한 미션은 goal_type 당 최대 1개 목표를 가진다.
# goal_type: approved_reports(승인 독후감 수)·game_plays(게임 완료 수). target_count 는 1 이상
# (DB CHECK + 모델 검증). 유니크 [mission_id, goal_type] 는 DB 인덱스와 모델 검증이 함께 보증한다.
class MissionGoal < ApplicationRecord
  belongs_to :mission

  enum :goal_type, { approved_reports: 0, game_plays: 1 }

  validates :goal_type, presence: true
  validates :goal_type, uniqueness: { scope: :mission_id }
  validates :target_count, numericality: { only_integer: true, greater_than: 0 }
end
