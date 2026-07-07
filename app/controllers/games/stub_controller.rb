module Games
  # 증분 게임(book/classic/battle/balance/vocab/whoami/marathon) 공통 플레이스홀더(P5.6).
  # 라우트만 살아 있고 "준비 중" 안내를 렌더한다. 실동작은 quiz/golden/bingo 참고.
  class StubController < BaseController
    # "준비 중" 안내만 렌더하는 플레이스홀더 — 인가할 리소스가 없다(표현용).
    skip_after_action :verify_authorized

    def show
      render "games/placeholder"
    end
  end
end
