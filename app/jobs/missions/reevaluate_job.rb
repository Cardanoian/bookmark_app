module Missions
  # 미션 완료·보상 주기 재평가(menu_refactor 심화 §2.A.6 안전망2). config/recurring.yml 에서 매시 실행.
  # 트리거 미스(이벤트 훅 누락·잡 실패)·지연배정 갭을 흡수하는 최종 백스톱이다. Rewarder 가 조건부
  # UPDATE(`WHERE rewarded_at IS NULL`)로 멱등이라 재실행이 안전하다.
  #
  # 대상: active + 최근 종료(종료 후 GRACE_DAYS 이내) published 미션의 미보상 participation.
  # 부하 제한(§2.A.6 O1): 종료 오래된 미션은 순회 제외, 미보상 행만. 완전 순회를 백스톱으로 둔다.
  class ReevaluateJob < ApplicationJob
    queue_as :default

    GRACE_DAYS = 3

    def perform
      rewarder = Rewarder.new
      candidate_missions.find_each do |mission|
        mission.mission_participations.where(rewarded_at: nil).find_each do |participation|
          rewarder.reward!(participation)
        end
      end
    end

    private

    def candidate_missions
      today = Date.current
      Mission.published
             .where(start_date: ..today)
             .where(end_date: (today - GRACE_DAYS)..)
             .where(id: MissionGoal.select(:mission_id))   # 목표 있는 미션만(m6 백스톱)
    end
  end
end
