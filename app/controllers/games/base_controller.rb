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

    # 게임 완료 활동 원장 1행을 멱등 기록한다(monster_unlocks.md §게임 판정, Phase 3B).
    # 같은 학생·게임·(책)·일자의 재제출은 부분 유니크 인덱스가 1회로 dedup 한다(RecordNotUnique 무해).
    # 새로 기록했으면 그 GamePlay 를, 중복/스킵이면 nil 을 반환한다(호출부는 신규 기록 시에만 해금 재평가).
    #
    # game_type 신뢰 경계: 퀴즈 4종(quiz/classic/vocab/whoami)은 mcq 를 공유하는 quiz·classic 을 서버가
    # Quiz 행만으론 구분할 수 없어(md §69) **검증된 클라이언트 선언(params[:game], 5값 allowlist)**을 표면으로
    # 기록한다 — md §69 "서버 결정 영속화" 이상과의 의도적 편차(저위험 자기이득). book 은 라우트로 서버 확정.
    # allowlist 밖 값은 기록하지 않는다(위조·미지 표면 방어). 학생만 기록한다(도감은 학생 전용).
    def record_game_play!(game_type:, book_id:)
      game_type = game_type.to_s
      return nil unless current_user&.student?
      return nil unless GamePlay.game_types.key?(game_type)

      current_user.game_plays.create!(
        game_type: game_type,
        book_id: book_id,
        played_on: Time.current.in_time_zone("Asia/Seoul").to_date
      )
    rescue ActiveRecord::RecordNotUnique
      nil
    end
  end
end
