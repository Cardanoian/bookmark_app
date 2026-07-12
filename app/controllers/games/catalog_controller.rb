module Games
  # 게임 카탈로그(Phase 3 §3.1). 학생이 **도서 → 게임**을 골라 온디맨드로 진입하는 관문.
  # 실동작 게임(playable) 목록 + 카탈로그 도서(추천/고전)를 보여 준다. 표현용 목록이라 인가 리소스가
  # 없어 verify_authorized 를 스킵한다(로그인은 ApplicationController 게이트가 이미 강제).
  class CatalogController < BaseController
    skip_after_action :verify_authorized, only: :index

    def index
      @games = CATALOG.select { |_key, meta| meta[:playable] }
      @books = Book.where(category: [ :recommended, :classic ]).order(:title)
    end
  end
end
