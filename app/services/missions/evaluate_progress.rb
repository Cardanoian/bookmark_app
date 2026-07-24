module Missions
  # 미션 진행 평가 단일 진입점(menu_refactor 심화 §2.A.3). 활동 확정 지점에서 관련 미션 후보를
  # 좁혀 Rewarder(멱등)를 호출한다. 클라이언트는 완료·지급을 직접 호출할 수 없다(서버 권위).
  class EvaluateProgress
    def initialize(user)
      @user = user
      @rewarder = Rewarder.new
    end

    # 독후감 교사 승인 직후. 원본(고쳐쓰기 제외) 승인 report 만.
    # M4: report.classroom_id(불변 스탬프)의 participation 을 타깃(unassigned 여부 무관) —
    # approved_reports_count 도 classroom_id 로 COUNT 하므로 count==trigger parity 가 성립한다.
    def on_report_approved(report)
      return unless report.reviewed? && report.revision_of_id.nil?

      date = report.created_at.in_time_zone(ProgressCalculator::ZONE).to_date
      report_candidates(classroom_id: report.classroom_id, date: date).each { |p| @rewarder.reward!(p) }
    end

    # 게임 신규 완료(GamePlay 원장 신규 행) 직후. game_plays 는 classroom 스탬프가 없어 현재 소속만
    # 타깃하고, ProgressCalculator 가 participation 기간 clamp 로 전학 후 플레이를 배제한다.
    def on_game_play(game_play)
      game_candidates(date: game_play.played_on).each { |p| @rewarder.reward!(p) }
    end

    # 편입 직후 즉시 평가(§2.A.6 안전망1) + ReevaluateJob(백스톱)이 공유하는 catch-up.
    # 이 유저의 미보상·published 미션 participation 전체를 재평가한다(편입 전 활동·트리거 미스 흡수).
    def evaluate_pending
      @user.mission_participations.where(rewarded_at: nil)
           .joins(:mission).merge(Mission.published)
           .each { |p| @rewarder.reward!(p) }
    end

    private

    def report_candidates(classroom_id:, date:)
      base(date: date, goal_type: :approved_reports)
        .where(missions: { classroom_id: classroom_id })            # unassigned 무관(M4 parity)
    end

    def game_candidates(date:)
      base(date: date, goal_type: :game_plays)
        .where(mission_participations: { unassigned_at: nil })      # 현재 소속만
        .where(missions: { classroom_id: @user.classroom_id })
    end

    def base(date:, goal_type:)
      @user.mission_participations
           .where(rewarded_at: nil)                                  # 미보상만(목표-0 가드는 Rewarder 내부 m6)
           .joins(:mission)
           .merge(Mission.published)
           .where("missions.start_date <= ? AND missions.end_date >= ?", date, date)
           .where(mission_id: MissionGoal.where(goal_type: goal_type).select(:mission_id))
    end
  end
end
