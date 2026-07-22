# 학생별 챌린지 참여·완료·보상 원장(챌린지 목표화 — MissionParticipation 미러). 챌린지당 학생 1행
# (유니크 [challenge_id, user_id]). completed_at 이 완료, rewarded_at + reward_points_awarded 가
# 정확히-1회 보상 원장이다(Challenges::Rewarder 가 조건부 UPDATE 로 선점). 미션과 달리 배정/해제
# 기간(assigned_at/unassigned_at)이 없다 — 전국/학교 스코프라 활동·조회 시 지연(lazy) 생성한다.
class ChallengeParticipation < ApplicationRecord
  belongs_to :challenge
  belongs_to :user

  validates :user_id, uniqueness: { scope: :challenge_id }
  validates :reward_points_awarded, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
