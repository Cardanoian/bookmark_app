module Missions
  # 미션 완료 보상의 정확히-1회 지급(menu_refactor 심화 §2.A.1). 반환: 이번 호출로 새로 지급된
  # participation(지급 안 했으면 nil).
  #
  # claim(조건부 UPDATE `WHERE rewarded_at IS NULL`)과 credit(credit_points!)을 한
  # ApplicationRecord.transaction 으로 감싸 **이중지급과 under-award 를 동시에 막는다**:
  #   - 이중지급: 미보상 상태 원자 선점(`affected == 1` 스레드만 통과) — 경쟁 스레드 B 는
  #     affected==0 → 크레딧 스킵. SQLite 에서 lock!/FOR UPDATE 는 no-op 이라 이 조건부 UPDATE 가
  #     정확히-1회의 단일 진실(spend_points! pointable.rb 관용구와 동일).
  #   - under-away: claim 커밋 후 credit 전 사망(컨테이너 스왑·OOM) 시 트랜잭션이 둘을 함께 롤백 →
  #     rewarded_at 이 nil 로 남아 ReevaluateJob 이 재포착.
  # credit_points! 는 update_counters 라 콜백·방송이 없어 트랜잭션 안에서 롤백 오염이 없다.
  # 방송·후크(run_point_side_effects!)만 커밋 후 실행(A1 방송 경계 불변).
  class Rewarder
    def reward!(participation)
      mission = participation.mission
      # m6: 목표-0/미발행 오지급 가드를 호출부가 아니라 여기 두어 reevaluate·잡 우회에도 성립시킨다.
      return nil if mission.mission_goals.empty? || !mission.published?
      return nil unless ProgressCalculator.new(mission, participation.user, participation: participation).completed?

      now = Time.current
      amount = mission.reward_points.to_i
      awarded = ApplicationRecord.transaction do
        affected = MissionParticipation
          .where(id: participation.id, rewarded_at: nil)                  # 미보상 원자 선점
          .update_all(
            completed_at: participation.completed_at || now,
            reward_points_awarded: amount,
            rewarded_at: now,
            updated_at: now
          )
        next false unless affected == 1                                   # 경쟁 스레드 B: 크레딧 스킵
        participation.user.credit_points!(amount)                         # 트랜잭션 안 원자 적립
        true
      end
      return nil unless awarded

      participation.reload
      participation.user.run_point_side_effects!                          # 뱃지·진화·랭킹 방송(커밋 후)
      participation
    end
  end
end
