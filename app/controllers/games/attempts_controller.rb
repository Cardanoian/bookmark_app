module Games
  # 독서게임 결과 기록(P5.6). quiz/golden/bingo 공통 제출 엔드포인트.
  # 채점 → QuizAttempt 생성 → award_points(레벨·진화·뱃지 연쇄) 후 게임 화면으로 복귀.
  class AttemptsController < BaseController
    def create
      quiz = Quiz.published.find(params[:quiz_id])
      authorize QuizAttempt.new(quiz: quiz, user: current_user), :create?

      attempt = QuizPlay.new(quiz: quiz, user: current_user).record!(submitted_answers)
      redirect_to game_path(params[:game], quiz),
                  notice: "#{attempt.score}문제 정답! #{attempt.score * QuizPlay::POINTS_PER_CORRECT}포인트를 얻었어요."
    end

    private

    # answers[question_id] = 선택 보기 인덱스. 인덱스만 정수로 사용(모델 대량 대입 아님).
    def submitted_answers
      raw = params[:answers]
      return {} unless raw.respond_to?(:each_pair)

      raw.to_unsafe_h.transform_keys(&:to_s).transform_values(&:to_i)
    end

    # 제출한 게임 종류에 맞는 게임 화면 경로(허용 목록만).
    def game_path(game, quiz)
      case game.to_s
      when "golden" then games_golden_path(quiz)
      when "bingo" then games_bingo_path(quiz)
      else games_quiz_path(quiz)
      end
    end
  end
end
