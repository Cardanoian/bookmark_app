module Challenges
  # 챌린지 진행 평가 단일 진입점(챌린지 목표화 — Missions::EvaluateProgress 미러 + 지연 참여).
  # 미션은 발행 시 학급 학생에게 participation 을 eager 배정하지만, 챌린지는 전국/학교 스코프라
  # 전원 배정이 비현실적이다. 따라서 활동 트리거(독후감 승인·게임 완료)와 상세 조회 시점에
  # **참여 대상(전국 + 소속 학교) + 활성(기간 내) + 해당 목표가 있는** 챌린지에 한해 participation 을
  # 지연 생성하고 Rewarder(멱등)를 호출한다. 클라이언트는 완료·지급을 직접 호출할 수 없다(서버 권위).
  class EvaluateProgress
    def initialize(user)
      @user = user
      @rewarder = Rewarder.new
    end

    # 독후감 교사 승인 직후. 원본(고쳐쓰기 제외) 승인 report 만.
    def on_report_approved(report)
      return unless report.reviewed? && report.revision_of_id.nil?

      candidate_challenges(goal_type: :approved_reports).each { |challenge| evaluate(challenge) }
    end

    # 게임 신규 완료(GamePlay 원장 신규 행) 직후.
    def on_game_play(_game_play)
      candidate_challenges(goal_type: :game_plays).each { |challenge| evaluate(challenge) }
    end

    # 챌린지 상세 조회 시 뷰어 학생 진행 평가(멱등, 지연 참여 생성). 활성 챌린지만 참여 행을 만든다.
    def evaluate(challenge)
      return unless @user.student?
      return unless challenge.has_goals?
      return unless challenge.active?

      participation = ChallengeParticipation.find_or_create_by!(challenge: challenge, user: @user)
      @rewarder.reward!(participation)
    rescue ActiveRecord::RecordNotUnique
      # 지연 생성 동시성 경합 — 이미 만들어진 행으로 재평가.
      participation = ChallengeParticipation.find_by(challenge: challenge, user: @user)
      @rewarder.reward!(participation) if participation
    end

    private

    # @user 가 참여 대상(전국 + 소속 학교)이며 해당 goal_type 목표가 있고 오늘 활성인 챌린지.
    def candidate_challenges(goal_type:)
      in_scope_challenges
        .where(id: ChallengeGoal.where(goal_type: goal_type).select(:challenge_id))
        .to_a
        .select(&:active?)
    end

    def in_scope_challenges
      Challenge.where(scope: :global)
               .or(Challenge.where(scope: :school, school_id: @user.school_id))
    end
  end
end
