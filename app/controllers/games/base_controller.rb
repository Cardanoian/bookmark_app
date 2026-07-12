module Games
  # 독서게임 10종 공통 베이스(P5.6). 게임 카탈로그(한국어 라벨) + published 퀴즈 로딩.
  class BaseController < ApplicationController
    # 게임 키 → 표시 이름. Phase 3 온디맨드 편입으로 **7종 실동작**(mcq 계열 quiz/golden/bingo/classic
    # + matching=vocab + hint_reveal=whoami + balance_vote=balance), **3종 증분 스텁**(book·battle=R3·marathon).
    # 실동작 게임은 카탈로그에서 도서를 골라 `play?book_id=` 로 온디맨드 진입한다(미스=오프라인 즉시).
    CATALOG = {
      "quiz" => { name: "독서 퀴즈", icon: "❓", surface: "quiz", playable: true },
      "golden" => { name: "골든벨 서바이벌", icon: "🔔", surface: "golden", playable: true },
      "bingo" => { name: "독서 빙고", icon: "🎉", surface: "bingo", playable: true },
      "classic" => { name: "고전 읽기 여행", icon: "🏛️", surface: "classic", playable: true },
      "vocab" => { name: "어휘 낚시", icon: "🎣", surface: "vocab", playable: true },
      "whoami" => { name: "나는 누구게?", icon: "🕵️", surface: "whoami", playable: true },
      "balance" => { name: "밸런스 게임", icon: "⚖️", surface: "balance", playable: true },
      "book" => { name: "책 소개 대결", icon: "📖", playable: false },
      "battle" => { name: "독서 배틀", icon: "⚔️", playable: false },
      "marathon" => { name: "독서 마라톤", icon: "🏃", playable: false }
    }.freeze

    private

    # published 퀴즈를 찾아 인가(QuizPolicy#show?)한 뒤 반환. 미게시/없음 → 404. 경계 클램프(band/학급,
    # §3.3)는 QuizPolicy 가 강제하므로 raw quiz_id(교사/system) 직접 플레이도 여기서 걸러진다.
    def load_playable_quiz
      quiz = Quiz.published.find(params[:id])
      authorize quiz, :show?
      quiz
    end

    # 온디맨드 진입 공통(§3.1): 도서 → 표면을 콘텐츠축으로 접어 캐시-우선 리졸브 → 즉시 렌더(무대기).
    # book 카탈로그 경계(BookPolicy)와 퀴즈 플레이 경계(QuizPolicy: band/학급)를 둘 다 인가한다.
    def resolve_on_demand(surface)
      book = Book.find(params[:book_id])
      authorize book, :show?
      quiz = Games::ContentProvider.resolve(book: book, surface: surface, user: current_user)
      authorize quiz, :show?
      quiz
    end

    def catalog_entry
      CATALOG.fetch(controller_name, { name: controller_name, icon: "🎮", playable: false })
    end
    helper_method :catalog_entry
  end
end
