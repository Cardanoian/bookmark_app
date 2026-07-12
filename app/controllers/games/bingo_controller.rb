module Games
  # 독서 빙고(P5.6 → Phase 3 온디맨드). 같은 mcq 콘텐츠축을 빙고판 그리드로.
  class BingoController < BaseController
    def show
      @quiz = load_playable_quiz
    end

    def play
      @quiz = resolve_on_demand("bingo")
      render :show
    end
  end
end
