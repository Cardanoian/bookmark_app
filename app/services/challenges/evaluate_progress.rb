module Challenges
  # 챌린지 진행 평가 단일 진입점(챌린지 목표화 — Missions::EvaluateProgress 미러).
  #
  # 미션은 발행 시 학급 학생에게 participation 을 eager 배정하지만, 챌린지는 전국/학교 스코프라
  # 전원 배정이 비현실적이다. 그래서 참여는 **학생이 '참여하기'를 누를 때만** 생성되고
  # (ChallengesController#join), 이 서비스는 **이미 참여한** 챌린지의 진행만 재평가한다.
  # 참여 원장이 없는 학생은 평가·보상 대상이 아니며, 진행 집계는 joined_at 이후 활동만 센다
  # (ProgressCalculator). 클라이언트는 완료·지급을 직접 호출할 수 없다(서버 권위).
  class EvaluateProgress
    def initialize(user)
      @user = user
      @rewarder = Rewarder.new
    end

    # 독후감 교사 승인 직후. 원본(고쳐쓰기 제외) 승인 report 만.
    def on_report_approved(report)
      return unless report.reviewed? && report.revision_of_id.nil?

      joined_challenges(goal_type: :approved_reports).each { |challenge| evaluate(challenge) }
    end

    # 게임 신규 완료(GamePlay 원장 신규 행) 직후.
    def on_game_play(_game_play)
      joined_challenges(goal_type: :game_plays).each { |challenge| evaluate(challenge) }
    end

    # 참여·조회 시점의 진행 평가(멱등). 참여 원장이 없으면 아무것도 하지 않는다(명시적 참여만 인정).
    # participation 을 이미 조회한 호출부(챌린지 상세)는 넘겨서 중복 쿼리를 피한다.
    def evaluate(challenge, participation: nil)
      return unless @user.student?
      return unless challenge.has_goals?
      return unless challenge.active?

      participation ||= ChallengeParticipation.find_by(challenge: challenge, user: @user)
      return if participation.nil?

      @rewarder.reward!(participation)
    end

    private

    # @user 가 **참여했고**(participation 존재) 참여 대상 스코프(전국 + 소속 학교)이며 해당 goal_type
    # 목표가 있고 오늘 활성인 챌린지. 스코프 조건은 join 게이트와 중복이지만 전학 등으로 경계를 벗어난
    # 뒤의 보상을 막는 안전망으로 남긴다.
    def joined_challenges(goal_type:)
      in_scope_challenges
        .where(id: ChallengeGoal.where(goal_type: goal_type).select(:challenge_id))
        .where(id: ChallengeParticipation.where(user: @user).select(:challenge_id))
        .to_a
        .select(&:active?)
    end

    def in_scope_challenges
      Challenge.where(scope: :global)
               .or(Challenge.where(scope: :school, school_id: @user.school_id))
    end
  end
end
