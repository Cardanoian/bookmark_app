module Games
  # 고전 읽기 여행(Phase 3 온디맨드). classic 표면은 mcq 콘텐츠축을 공유한다(N1). play=book_id 진입.
  class ClassicController < BaseController
    def play
      @quiz = resolve_on_demand("classic")
      render :show
    end
  end
end
