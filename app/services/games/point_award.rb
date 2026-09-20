module Games
  # 멱등 델타 적립의 상한(prior ceiling)을 quiz.origin 으로 분기한다(Phase 1 §1.3, A1).
  #
  #   teacher : per-quiz 상한 — 이 학생이 **이 퀴즈**에서 받은 최고 적립액(현행 멱등 그대로).
  #             재플레이 +0(엉뚱한 system 행을 읽지 않는다 — C5a 회귀 가드).
  #   system  : 콘텐츠축 상한 — 이 학생이 같은 (book, band, content_axis) 의 **system 퀴즈들**에서
  #             받은 최고 적립액. 다시 뽑기(새 content_version)·표면 전환도 +0.
  #
  # 공통 불변식: delta = [this_score − prior_max, 0].max 만 적립하고,
  # QuizAttempt.points_awarded 에는 (델타가 아니라) this_score 를 저장한다 — maximum() 상한이
  # 성립하려면 저장값이 "이번 점수 기준 만점 적립액"이어야 한다. 절대 델타로 저장하지 말 것.
  #
  # **이 클래스는 계산만 한다**(BUG_FIX_PLAN F1). 상한 조회 → attempt 확정 → 적립이 한 트랜잭션 안에서
  # 이어져야 하므로 적립은 그 트랜잭션을 가진 QuizPlay 가 `credit_points!` 로 한다. 예전의 `award!` 는
  # attempt 를 저장한 뒤 트랜잭션 밖에서 상한을 읽고 `award_points` 를 불렀다 — 확정된 attempt 를 다시
  # 제출하면 바로 그 행이 `excluding:` 으로 빠져 상한이 0 으로 돌아갔고, 새 attempt 두 개가 동시에
  # 저장되면 서로를 제외해 읽어 양쪽 다 전액(또는 양쪽 다 0)이 됐다.
  class PointAward
    def initialize(quiz:, user:)
      @quiz = quiz
      @user = user
    end

    # this_score 가 이전 최고 적립액을 넘는 만큼(지급할 차액). **확정·적립과 같은 트랜잭션 안에서** 부른다.
    # excluding: 아직 확정하지 않은 이번 판 attempt(whoami 선생성 행 — points_awarded 0 이라 상한에
    # 영향은 없지만, "이번 판 이전의 최고액"이라는 뜻을 분명히 한다).
    def delta_for(this_score, excluding: nil)
      [ this_score.to_i - prior_max(excluding: excluding), 0 ].max
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
