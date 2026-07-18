module Games
  # 게임 카탈로그(Phase 3 §3.1). 학생이 **도서 → 게임**을 골라 온디맨드로 진입하는 관문.
  # 실동작 게임(playable) 목록만 서버가 넘기고, 도서는 전량 로드 대신 **폼리스 도서 검색**
  # (/books/autocomplete)으로 클라이언트에서 고른다(무한 증가·전량 로드 제거). 표현용 목록이라
  # 인가 리소스가 없어 verify_authorized 를 스킵한다(로그인은 ApplicationController 게이트가 이미 강제).
  class CatalogController < BaseController
    skip_after_action :verify_authorized, only: :index

    def index
      @games = CATALOG.select { |_key, meta| meta[:playable] }
    end
  end
end
