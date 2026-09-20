module Games
  # 독서게임 채점·기록(P5.6). 제출 답안을 published 퀴즈의 정답과 대조해 점수를 내고, QuizAttempt 확정 ·
  # 포인트 적립 · 완료 원장(GamePlay) 기록을 **한 트랜잭션**으로 남긴다(BUG_FIX_PLAN F1·F4).
  # 포인트 후크(뱃지·진화·랭킹 방송)는 커밋 뒤에 돌려 Phase 4 게임화에 반영한다.
  class QuizPlay
    # 정답 1개당 지급 포인트(퀴즈 5문항 만점 ≈ 독후감 1편 수준으로 균형).
    # 채점 스케일의 단일 진실은 QuestionScorer — 여기서는 하위호환 참조만 노출한다.
    POINTS_PER_CORRECT = QuestionScorer::POINTS_PER_CORRECT

    # SQLite 쓰기 잠금을 제때 못 잡았을 때(다른 연결이 쓰는 중) 트랜잭션 전체를 다시 해 보는 횟수.
    BUSY_RETRY_LIMIT = 2

    # 받을 수 없는 퀴즈(matching·알 수 없는 축·축과 문항 구성이 어긋난 퀴즈 — Quiz#play_game_type 이 nil).
    # 컨트롤러가 먼저 거르므로 정상 흐름에서는 나지 않는다 — 저장·채점·보상 전에 멈추는 이중 방어다.
    class UnsupportedQuiz < StandardError; end

    # record! 의 결과. attempt=저장된(또는 이미 확정돼 있던) 기록, awarded_delta=이번에 실제로 적립한 포인트,
    # newly_finalized=이번 호출이 그 attempt 를 확정했는가(같은 attempt 재전송이면 false),
    # game_play=이번에 새로 생긴 완료 원장 행(같은 날 이미 있었거나 재전송이면 nil).
    # **"추가 포인트 0"과 "재전송"은 다르다** — 최고점을 못 넘은 정상 새 판은 newly_finalized 가 참이다.
    Result = Data.define(:attempt, :awarded_delta, :newly_finalized, :game_play) do
      delegate :score, :points_awarded, to: :attempt

      def newly_finalized? = newly_finalized
    end

    # attempt: whoami(hint_reveal) 는 게임 시작 시 attempt 를 선생성(reveal_hint 가 :attempt 요구,
    # EXECUTOR-NOTE #2)하므로 제출 시 그 선생성 행을 넘겨 finalize 한다. 없으면(mcq)
    # 제출 시 새 attempt 를 만든다.
    def initialize(quiz:, user:, attempt: nil)
      if attempt && (attempt.user_id != user.id || attempt.quiz_id != quiz.id)
        raise ArgumentError, "attempt does not belong to this user and quiz"
      end

      @quiz = quiz
      @user = user
      @attempt = attempt
    end

    # answers: { "<question_id>" => 타입별 응답 } 해시. 반환: Result.
    #
    # 멱등 적립(§1.2): 매 제출마다 만점을 재지급하면 같은 퀴즈를 반복 제출해 포인트를
    # 무제한 파밍할 수 있다. 그래서 이 학생이 이미 받은 최고 적립액을 기준으로
    # 초과분(delta)만 지급한다. 첫 만점은 전액, 재플레이는 0, 더 높은 점수는 증가분만.
    #
    # 완료된 attempt 는 다시 바뀌지 않는다(F1): 선생성 attempt 의 played_at 이 이미 있으면 답안이 달라도
    # 저장된 결과를 그대로 돌려주고 보상·완료 기록을 더하지 않는다. 날짜를 넘겨 도착한 재전송도 같다.
    def record!(answers)
      game_type = @quiz.play_game_type
      raise UnsupportedQuiz, "quiz #{@quiz.id} has no playable game type" unless game_type

      normalized = normalize(answers)
      result = with_busy_retry { finalize!(normalized, game_type) }
      # 지급은 이미 커밋됐다. 후크·방송이 실패해도 지급 트랜잭션을 다시 하지 않는다(재지급 금지).
      @user.run_point_side_effects! if result.awarded_delta.positive?
      result
    end

    private

    # 상한 조회 → attempt 확정 → 적립 → 완료 원장을 한 트랜잭션으로. SQLite 어댑터는 트랜잭션을
    # BEGIN IMMEDIATE 로 열어 DB 쓰기 잠금을 먼저 잡으므로(FOR UPDATE 는 무시된다), 이 블록은 다른 연결의
    # 같은 블록과 차례로 돈다 — 판단에 쓰는 값(완료 여부·힌트 공개수·이전 최고액)을 **이 안에서** 다시 읽는다.
    # 밖에서 읽은 값으로 판단하면 같은 attempt 의 동시 제출이 둘 다 "미완료"를 보고, 같은 보상 범위의
    # 서로 다른 attempt 가 서로를 못 본 채 전액을 받는다.
    def finalize!(normalized, game_type)
      ApplicationRecord.transaction do
        @attempt&.lock! # SQLite 에서는 재조회다(완료 여부·힌트 공개수를 지금 값으로).
        next replayed_result if @attempt&.played_at

        correct, this_award = score(normalized)
        delta = PointAward.new(quiz: @quiz, user: @user).delta_for(this_award, excluding: @attempt)

        # points_awarded 에는 (실지급 델타가 아니라) 이번 점수 기준 만점 적립액 this_award 를
        # 저장한다 — 상한 maximum() 불변식에 필요. 델타로 바꾸면 15→25→15→25 순서에서 파밍이
        # 재발하므로 절대 delta 로 바꾸지 말 것.
        attempt = persist_attempt(normalized, correct, this_award)
        next replayed_result unless attempt

        @user.credit_points!(delta)
        # 완료 원장은 확정과 같은 트랜잭션에 둔다 — 따로 커밋하면 그 사이에 중단됐을 때 확정은 됐는데
        # 원장이 빠지고, 이후 재전송은 newly_finalized=false 라 복구되지 않는다. 같은 날의 기존 행과
        # 부딪히는 것은 record_daily! 의 savepoint 가 흡수한다(확정·적립은 유지).
        game_play = GamePlay.record_daily!(user: @user, game_type: game_type, book_id: @quiz.book_id)

        Result.new(attempt: attempt, awarded_delta: delta, newly_finalized: true, game_play: game_play)
      end
    end

    # 이미 확정된 선생성 attempt 의 재전송 — 저장된 결과 그대로, 보상·완료 기록 없음.
    def replayed_result
      Result.new(attempt: @attempt, awarded_delta: 0, newly_finalized: false, game_play: nil)
    end

    # 타입별 채점은 QuestionScorer 로 위임(§1.2). hint_reveal 은 **서버 권위 힌트수**(선생성
    # attempt 의 hint_reveals 컬럼)만 신뢰해 차감한다(C1) — 클라이언트가 보낸 힌트수는 무시한다.
    # 반환: [정답 수, 이번 점수 기준 적립액].
    def score(normalized)
      correct = 0
      this_award = 0
      @quiz.quiz_questions.each do |question|
        outcome = QuestionScorer.for(question).score(normalized[question.id.to_s], hints_used: server_hints_used(question))
        correct += 1 if outcome[:correct]
        this_award += outcome[:score]
      end
      [ correct, this_award ]
    end

    # 서버 권위 힌트 공개수(hint_reveal 만 의미 있음).
    def server_hints_used(question)
      return @attempt.revealed_count(question) if @attempt

      # 선생성 attempt 가 없는데 hint_reveal 문항이면(=바인딩 유실/우회 시도) **최대 페널티**로
      # fail-safe 한다. attempt_id 를 빼고 제출해 hints_used=0 으로 만점받는 우회(H1)를 원천 차단.
      # 정상 whoami 는 AttemptsController 가 선생성 attempt 를 강제하므로 이 경로에 도달하지 않는다.
      # mcq 는 hints_used 를 무시하므로 0 이 안전하다.
      question.question_type == "hint_reveal" ? question.hints_list.length : 0
    end

    # 선생성 attempt(whoami)면 **미완료일 때만** 확정하고(`WHERE played_at IS NULL` — 0행이면 다른 요청이
    # 먼저 확정한 것이라 nil), 아니면 새 attempt 를 만든다. 객관식은 선생성 attempt 가 없어 재전송을 같은
    # 요청으로 알아볼 수 없다 — 새 판으로 받되 보상은 차액 상한이, 완료 원장은 일일 유니크가 묶는다.
    def persist_attempt(normalized, correct, this_award)
      now = Time.current
      attributes = { score: correct, answers: normalized, points_awarded: this_award, played_at: now }
      return @quiz.quiz_attempts.create!(attributes.merge(user: @user)) unless @attempt

      finalized = QuizAttempt.where(id: @attempt.id, played_at: nil).update_all(attributes.merge(updated_at: now))
      finalized == 1 ? @attempt.reload : nil
    end

    # 다른 연결이 쓰기 잠금을 쥐고 있어 제때 못 들어가면(SQLite busy → StatementTimeout) 트랜잭션 전체가
    # 롤백된 뒤이므로 처음부터 다시 해도 중복 지급이 없다. 횟수를 묶고, 바깥 트랜잭션에 합류해 돌던 중이면
    # (여기서 되돌린 것이 아니다) 다시 하지 않는다. 커밋 뒤의 후크·방송 실패는 이 재시도 밖이다.
    def with_busy_retry
      tries = 0
      begin
        yield
      rescue ActiveRecord::StatementTimeout
        tries += 1
        raise if tries > BUSY_RETRY_LIMIT || ApplicationRecord.connection.transaction_open?

        retry
      end
    end

    # 채점기가 타입별로 coerce 하므로(mcq=인덱스, matching=쌍맵 해시, hint_reveal=텍스트)
    # 여기서는 to_i 로 뭉개지 않고 키만 문자열화해 원형을 보존한다. 중첩 파라미터는
    # 채점 가능한 순수 해시로 편다.
    def normalize(answers)
      return {} unless answers.respond_to?(:each_pair)

      answers.each_with_object({}) do |(key, value), memo|
        memo[key.to_s] = coerce(value)
      end
    end

    def coerce(value)
      case value
      when ActionController::Parameters then value.to_unsafe_h
      when Hash then value.transform_keys(&:to_s)
      else value
      end
    end
  end
end
