module Games
  # 골든벨 서바이벌(P5.6 → Phase 3 온디맨드). 같은 mcq 콘텐츠축을 서바이벌 UI 로.
  class GoldenController < BaseController
    def show
      @quiz = load_playable_quiz
    end

    def play
      @quiz = resolve_on_demand("golden")
      render :show
    end
  end
end
