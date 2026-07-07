module Games
  # 독서게임(quiz/golden/bingo) 채점·기록(P5.6). 제출 답안을 published 퀴즈의 정답과
  # 대조해 점수를 내고 QuizAttempt 를 남긴 뒤, User#award_points 로 포인트를 지급한다.
  # 포인트 지급이 Leveling/Evolvable/Badgeable 로 연쇄되어 Phase 4 게임화에 반영된다.
  class QuizPlay
    # 정답 1개당 지급 포인트(퀴즈 5문항 만점 ≈ 독후감 1편 수준으로 균형).
    POINTS_PER_CORRECT = 5

    def initialize(quiz:, user:)
      @quiz = quiz
      @user = user
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
      correct = @quiz.quiz_questions.count { |question| question.correct?(normalized[question.id.to_s]) }
      this_award = correct * POINTS_PER_CORRECT

      # 이번 판을 만들기 전, 이 학생이 이 퀴즈에서 이미 받은 최고 적립액.
      previously_awarded = @quiz.quiz_attempts.where(user: @user).maximum(:points_awarded).to_i
      delta = [ this_award - previously_awarded, 0 ].max

      # points_awarded 에는 (실지급 델타가 아니라) 이번 점수 기준 만점 적립액 this_award 를
      # 저장한다 — previously_awarded 의 maximum() 불변식에 필요. 델타로 바꾸면 15→25→15→25
      # 같은 순서에서 파밍이 재발하므로 절대 delta 로 바꾸지 말 것.
      attempt = @quiz.quiz_attempts.create!(
        user: @user,
        score: correct,
        answers: normalized,
        points_awarded: this_award,
        played_at: Time.current
      )
      @user.award_points(delta, reason: "game_quiz")
      attempt.awarded_delta = delta
      attempt
    end

    private

    def normalize(answers)
      return {} unless answers.respond_to?(:each_pair)

      answers.each_with_object({}) do |(key, value), memo|
        memo[key.to_s] = value.to_i
      end
    end
  end
end
