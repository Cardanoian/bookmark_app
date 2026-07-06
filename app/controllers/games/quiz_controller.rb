module Games
  # 독서 퀴즈(실동작, P5.6). published 퀴즈 문항을 4지선다로 풀어 games/attempts 로 제출.
  class QuizController < BaseController
    def show
      @quiz = load_playable_quiz
    end
  end
end
