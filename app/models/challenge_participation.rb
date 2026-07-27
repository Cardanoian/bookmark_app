# 학생별 챌린지 참여·완료·보상 원장(챌린지 목표화 — MissionParticipation 미러). 챌린지당 학생 1행
# (유니크 [challenge_id, user_id]). completed_at 이 완료, rewarded_at + reward_points_awarded 가
# 정확히-1회 보상 원장이다(Challenges::Rewarder 가 조건부 UPDATE 로 선점).
#
# **이 행의 존재 = 참여**다. 전국/학교 스코프라 미션처럼 발행 시 eager 배정하지 않고, 학생이
# '참여하기'를 누를 때(ChallengesController#join) 생성한다. joined_at(참여 시각)은 진행 집계 창의
# 하한이므로(Challenges::ProgressCalculator) **참여 후 활동만 목표에 인정**된다 — 재참여로 시작점이
# 미래로 밀리지 않도록 join 은 멱등하게 기존 행을 재사용한다. 미션의 assigned_at/unassigned_at 처럼
# 배정·해제 기간은 없다(참여 해제 개념 없음).
class ChallengeParticipation < ApplicationRecord
  belongs_to :challenge
  belongs_to :user

  validates :user_id, uniqueness: { scope: :challenge_id }
  validates :joined_at, presence: true
  validates :reward_points_awarded, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
