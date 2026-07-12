module Games
  # 독서 퀴즈(P5.6 → Phase 3 온디맨드). show=교사 published 퀴즈(id), play=온디맨드(book_id) mcq.
  class QuizController < BaseController
    def show
      @quiz = load_playable_quiz
    end

    def play
      @quiz = resolve_on_demand("quiz")
      render :show
    end
  end
end
