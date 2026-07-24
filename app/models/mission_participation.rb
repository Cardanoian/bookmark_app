# 학생별 미션 참여·완료·보상 원장(menu_refactor 심화 §2.A.5). 미션당 학생 1행(유니크
# [mission_id, user_id]). completed_at 이 완료(몬스터 지표) 단일 진실이고, rewarded_at +
# reward_points_awarded 가 정확히-1회 보상 원장이다(PR3 Rewarder 가 조건부 UPDATE 로 선점).
class MissionParticipation < ApplicationRecord
  belongs_to :mission
  belongs_to :user

  validates :user_id, uniqueness: { scope: :mission_id }
  validates :reward_points_awarded, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
