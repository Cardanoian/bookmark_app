module Games
  # 독서게임(quiz/golden/bingo) 채점·기록(P5.6). 제출 답안을 published 퀴즈의 정답과
  # 대조해 점수를 내고 QuizAttempt 를 남긴 뒤, User#award_points 로 포인트를 지급한다.
  # 포인트 지급이 Leveling/Evolvable/Badgeable 로 연쇄되어 Phase 4 게임화에 반영된다.
  class QuizPlay
    # 정답 1개당 지급 포인트(퀴즈 5문항 만점 ≈ 독후감 1편 수준으로 균형).
    # 채점 스케일의 단일 진실은 QuestionScorer — 여기서는 하위호환 참조만 노출한다.
    POINTS_PER_CORRECT = QuestionScorer::POINTS_PER_CORRECT

    # attempt: whoami(hint_reveal) 는 게임 시작 시 attempt 를 선생성(reveal_hint 가 :attempt 요구,
    # EXECUTOR-NOTE #2)하므로 제출 시 그 선생성 행을 넘겨 finalize 한다. 없으면(mcq/matching 등)
    # 제출 시 새 attempt 를 만든다.
    def initialize(quiz:, user:, attempt: nil)
      @quiz = quiz
      @user = user
      @attempt = attempt
    end

    # answers: { "<question_id>" => 선택 보기 인덱스 } 해시.
    # 반환: 생성된 QuizAttempt(award_points 후 — quizzes 집계에 이번 판이 포함된다).
    #
    # 멱등 적립(§1.2): 매 제출마다 만점을 재지급하면 같은 퀴즈를 반복 제출해 포인트를
    # 무제한 파밍할 수 있다. 그래서 이 학생이 이 퀴즈에서 이미 받은 최고 적립액을 기준으로
    # 초과분(delta)만 지급한다. 첫 만점은 전액, 재플레이는 0, 더 높은 점수는 증가분만.
    # (독후감 재첨삭의 report.points_awarded 델타 패턴 재사용 — ai_review_job.rb 참고.)
    def record!(answers)
      normalized = normalize(answers)

      # 타입별 채점은 QuestionScorer 로 위임(§1.2). hint_reveal 은 **서버 권위 힌트수**(선생성
      # attempt 의 hint_reveals 컬럼)만 신뢰해 차감한다(C1) — 클라이언트가 보낸 힌트수는 무시한다.
      correct = 0
      this_award = 0
      @quiz.quiz_questions.each do |question|
        outcome = QuestionScorer.for(question).score(normalized[question.id.to_s], hints_used: server_hints_used(question))
        correct += 1 if outcome[:correct]
        this_award += outcome[:score]
      end

      # points_awarded 에는 (실지급 델타가 아니라) 이번 점수 기준 만점 적립액 this_award 를
      # 저장한다 — 상한 maximum() 불변식에 필요. 델타로 바꾸면 15→25→15→25 순서에서 파밍이
      # 재발하므로 절대 delta 로 바꾸지 말 것.
      attempt = persist_attempt(normalized, correct, this_award)

      # 상한/델타는 PointAward 로 위임 — quiz.origin 으로 분기(teacher=per-quiz, system=콘텐츠축).
      # 방금 만든 이번 판 attempt 는 상한 계산에서 제외한다("생성 전 상한" 의미 보존).
      delta = PointAward.new(quiz: @quiz, user: @user)
                        .award!(this_award, reason: "game_quiz", excluding: attempt)
      attempt.awarded_delta = delta
      attempt
    end

    private

    # 서버 권위 힌트 공개수(hint_reveal 만 의미 있음).
    def server_hints_used(question)
      return @attempt.revealed_count(question) if @attempt

      # 선생성 attempt 가 없는데 hint_reveal 문항이면(=바인딩 유실/우회 시도) **최대 페널티**로
      # fail-safe 한다. attempt_id 를 빼고 제출해 hints_used=0 으로 만점받는 우회(H1)를 원천 차단.
      # 정상 whoami 는 AttemptsController 가 선생성 attempt 를 강제하므로 이 경로에 도달하지 않는다.
      # mcq/matching 등은 hints_used 를 무시하므로 0 이 안전하다.
      question.question_type == "hint_reveal" ? question.hints_list.length : 0
    end

    # 선생성 attempt(whoami)면 finalize, 아니면 새 attempt 생성.
    def persist_attempt(normalized, correct, this_award)
      attributes = { score: correct, answers: normalized, points_awarded: this_award, played_at: Time.current }
      if @attempt
        @attempt.update!(attributes)
        @attempt
      else
        @quiz.quiz_attempts.create!(attributes.merge(user: @user))
      end
    end

    # 채점기가 타입별로 coerce 하므로(mcq=인덱스, matching=쌍맵 해시, hint_reveal=텍스트)
    # 여기서는 to_i 로 뭉개지 않고 키만 문자열화해 원형을 보존한다. matching 의 중첩 파라미터는
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
