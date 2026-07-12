module Games
  # 밸런스 게임(Phase 3 온디맨드). balance 표면 → balance_vote 콘텐츠축(무정답 → 참여만, 0점).
  # 참여 포인트 부여는 Phase 4. play=book_id 진입.
  class BalanceController < BaseController
    def play
      @quiz = resolve_on_demand("balance")
      render :show
    end
  end
end
