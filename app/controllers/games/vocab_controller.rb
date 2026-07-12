module Games
  # 어휘 낚시(Phase 3 온디맨드, §3.2a matching). vocab 표면 → matching 콘텐츠축. play=book_id 진입.
  class VocabController < BaseController
    def play
      @quiz = resolve_on_demand("vocab")
      render :show
    end
  end
end
