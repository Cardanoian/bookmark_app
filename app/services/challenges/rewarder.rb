module Challenges
  # 챌린지 완료 보상의 정확히-1회 지급(챌린지 목표화 — Missions::Rewarder 미러). 반환: 이번 호출로
  # 새로 지급된 participation(지급 안 했으면 nil).
  #
  # claim(조건부 UPDATE `WHERE rewarded_at IS NULL`)과 credit(credit_points!)을 한
  # ApplicationRecord.transaction 으로 감싸 이중지급·under-award 를 동시에 막는다(Rewarder 관용구).
  # 방송·후크(run_point_side_effects!)만 커밋 후 실행(방송 경계 불변).
  #
  # 미션과 달리 published/active 게이트가 없다 — 챌린지는 발행 개념이 없고, 완료 인정 기간은
  # ProgressCalculator 의 window(생성일~ends_on)가 강제하므로 창 밖 활동은 애초에 카운트되지 않는다.
  # (기간이 지난 뒤 확인해도, 창 안 활동으로 목표를 채웠다면 보상은 정직하게 지급한다.)
  class Rewarder
    def reward!(participation)
      challenge = participation.challenge
      # 목표-0 챌린지 오지급 가드(호출부가 아니라 여기 둬 어떤 경로에도 성립).
      return nil if challenge.challenge_goals.empty?
      return nil unless ProgressCalculator.new(challenge, participation.user, participation: participation).completed?

      now = Time.current
      amount = challenge.reward_points.to_i
      awarded = ApplicationRecord.transaction do
        affected = ChallengeParticipation
          .where(id: participation.id, rewarded_at: nil)                  # 미보상 원자 선점
          .update_all(
            completed_at: participation.completed_at || now,
            reward_points_awarded: amount,
            rewarded_at: now,
            updated_at: now
          )
        next false unless affected == 1                                   # 경쟁 스레드: 크레딧 스킵
        participation.user.credit_points!(amount) if amount.positive?     # 트랜잭션 안 원자 적립
        true
      end
      return nil unless awarded

      participation.reload
      participation.user.run_point_side_effects! if amount.positive?      # 뱃지·진화·랭킹 방송(커밋 후)
      participation
    end
  end
end
