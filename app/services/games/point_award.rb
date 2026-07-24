module Games
  # 멱등 델타 적립의 상한(prior ceiling)을 quiz.origin 으로 분기한다(Phase 1 §1.3, A1).
  #
  #   teacher : per-quiz 상한 — 이 학생이 **이 퀴즈**에서 받은 최고 적립액(현행 멱등 그대로).
  #             재플레이 +0(엉뚱한 system 행을 읽지 않는다 — C5a 회귀 가드).
  #   system  : 콘텐츠축 상한 — 이 학생이 같은 (book, band, content_axis) 의 **system 퀴즈들**에서
  #             받은 최고 적립액. 다시 뽑기(새 content_version)·표면 전환도 +0.
  #
  # 공통 불변식: delta = [this_score − prior_max, 0].max 만 award_points 하고,
  # QuizAttempt.points_awarded 에는 (델타가 아니라) this_score 를 저장한다 — maximum() 상한이
  # 성립하려면 저장값이 "이번 점수 기준 만점 적립액"이어야 한다. 절대 델타로 저장하지 말 것.
  class PointAward
    def initialize(quiz:, user:)
      @quiz = quiz
      @user = user
    end

    # this_score 초과분(delta)을 적립하고 실지급 델타를 반환한다.
    # excluding: 방금 만든 이번 판 attempt(상한 계산에서 제외 — 원래 "생성 전 상한" 의미 보존).
    def award!(this_score, reason:, excluding: nil)
      delta = [ this_score.to_i - prior_max(excluding: excluding), 0 ].max
      @user.award_points(delta, reason: reason)
      delta
    end

    # origin 별 이번 판 이전 최고 적립액.
    def prior_max(excluding: nil)
      scope =
        if @quiz.origin == "system"
          QuizAttempt.where(user: @user, quiz_id: sibling_system_quiz_ids)
        else
          @quiz.quiz_attempts.where(user: @user)
        end
      scope = scope.where.not(id: excluding.id) if excluding&.persisted?
      scope.maximum(:points_awarded).to_i
    end

    private

    # 같은 콘텐츠축(book × band × content_axis)의 system 퀴즈 id 집합(부분쿼리).
    # enum 조건은 Quiz 모델 위에서 걸어 정수로 정확히 캐스팅된다(join-hash 캐스팅 모호성 회피).
    def sibling_system_quiz_ids
      Quiz.where(
        origin: :system,
        book_id: @quiz.book_id,
        band: @quiz.band,
        content_axis: @quiz.content_axis
      ).select(:id)
    end
  end
end
