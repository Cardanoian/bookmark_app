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
    def record!(answers)
      normalized = normalize(answers)
      correct = @quiz.quiz_questions.count { |question| question.correct?(normalized[question.id.to_s]) }

      attempt = @quiz.quiz_attempts.create!(
        user: @user,
        score: correct,
        answers: normalized,
        played_at: Time.current
      )
      @user.award_points(correct * POINTS_PER_CORRECT, reason: "game_quiz")
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
