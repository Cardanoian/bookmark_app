module Games
  # 독서 빙고(실동작, P5.6). 문항을 빙고판(그리드)으로 배치해 풀고 제출한다.
  class BingoController < BaseController
    def show
      @quiz = load_playable_quiz
    end
  end
end
