module Games
  # 독서게임 5종 공통 베이스(P5.6). 게임 카탈로그(한국어 라벨) + published 퀴즈 로딩.
  class BaseController < ApplicationController
    # 게임 키 → 표시 이름. **교육 다양성 우선 5종**: 퀴즈 파이프라인 4종(mcq=quiz·classic +
    # matching=vocab + hint_reveal=whoami)과 소셜 도메인 1종(book=책 소개 대결, Gemini 미호출).
    # 모두 카탈로그에서 도서를 골라 `play?book_id=` 로 진입한다(퀴즈 4종은 미스=오프라인 즉시).
    CATALOG = {
      "quiz" => { name: "독서 퀴즈", icon: "❓", surface: "quiz", playable: true },
      "classic" => { name: "고전 읽기 여행", icon: "🏛️", surface: "classic", playable: true },
      "vocab" => { name: "어휘 낚시", icon: "🎣", surface: "vocab", playable: true },
      "whoami" => { name: "나는 누구게?", icon: "🕵️", surface: "whoami", playable: true },
      "book" => { name: "책 소개 대결", icon: "📖", playable: true }
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
  end
end
