module Games
  # 독서게임 공통 베이스(P5.6 → 게임 재구성 Phase 1·2). 게임 카탈로그(한국어 라벨) + published 퀴즈 로딩.
  class BaseController < ApplicationController
    # 게임 키 → 표시 이름. **게임 재구성 Phase 1·2 4종**: 퀴즈 파이프라인 2종(mcq=quiz[고전 통합] +
    # hint_reveal=whoami)과 창작 소셜 도메인 2종(book=책 소개 대결·sequel=뒷이야기 이어쓰기, Gemini는
    # sequel 만 학생 글 격려 코멘트에 호출). 모두 카탈로그에서 도서를 골라 `play?book_id=` 로 진입한다
    # (퀴즈 2종은 미스=오프라인 즉시, 소셜 2종은 항상 가능). classic(→quiz 통합)·vocab(hard-delete) 표면은
    # 제거됐다(game_type enum 의 classic:1 은 과거 기록 보존차 유지).
    CATALOG = {
      "quiz" => { name: "독서 퀴즈", icon: :quiz, surface: "quiz", playable: true },
      "whoami" => { name: "나는 누구게?", icon: :detective, surface: "whoami", playable: true },
      "book" => { name: "책 소개 대결", icon: :book_open, playable: true },
      "sequel" => { name: "뒷이야기 이어쓰기", icon: :writing, playable: true }
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
    #
    # 가용성 게이트(Phase 4 §2c)는 `content_gate_allows?` 로 위임(아래) — 통과 못 하면 이미
    # 리다이렉트가 수행되어 있으므로(`performed?` true) nil 을 반환하고, 호출 컨트롤러는 nil 을
    # 받으면 렌더하지 않는다.
    def resolve_on_demand(surface)
      book = Book.find(params[:book_id])
      authorize book, :show?
      return nil unless content_gate_allows?(book, surface)

      quiz = Games::ContentProvider.resolve(book: book, surface: surface, user: current_user)
      authorize quiz, :show?
      quiz
    end

    # 가용성 게이트 공통 판정(Phase 4 §2c). `resolve_on_demand`(quiz/whoami play) 뿐 아니라
    # `RegenerateController#create`(다시 뽑기)도 같은 판정을 재사용해, 조작된 재생성 POST 로
    # 비활성 책에 오프라인 Quiz 를 물질화하는 우회를 막는다. surface 가 SURFACE_MAP 밖(book·
    # sequel)이면 게이트 대상이 아니라 true. 대상 표면(quiz→mcq·whoami→hint_reveal)이면
    # `game_content_available?` 로 판정하고, 아니면 **오프라인 일반 문제를 서빙/재생성하지 말고**
    # 독서활동으로 리다이렉트한 뒤 false 를 반환한다(콘텐츠 미생성 — resolve/regenerate 를 안 부름).
    def content_gate_allows?(book, surface)
      content_axis = Games::ContentProvider::SURFACE_MAP[surface.to_s]
      return true unless content_axis
      return true if Games::ContentProvider.game_content_available?(book: book, content_axis: content_axis, user: current_user)

      redirect_to reading_activity_path(book_id: book.id),
                  notice: "이 책은 아직 퀴즈가 없어요. 직접 문제를 내보거나 다른 활동을 해보세요!"
      false
    end

    # 게임 완료 활동 원장 1행을 멱등 기록한다(monster_unlocks.md §게임 판정, Phase 3B).
    # 같은 학생·게임·(책)·일자의 재제출은 부분 유니크 인덱스가 1회로 dedup 한다(RecordNotUnique 무해).
    # 새로 기록했으면 그 GamePlay 를, 중복/스킵이면 nil 을 반환한다(호출부는 신규 기록 시에만 해금 재평가).
    #
    # game_type 신뢰 경계: 퀴즈 표면(quiz/whoami)은 서버가 Quiz 행만으론 표면을 권위적으로 구분할 수
    # 없어(md §69) **검증된 클라이언트 선언(params[:game], GamePlay.game_types allowlist)**을 표면으로
    # 기록한다 — md §69 "서버 결정 영속화" 이상과의 의도적 편차(저위험 자기이득). book 은 라우트로 서버 확정.
    # allowlist 밖 값은 기록하지 않는다(위조·미지 표면 방어). vocab 은 enum 에서 빠져 자동 거부되고,
    # classic 은 enum 에 남아(과거 기록 보존) 옛 경로가 무해하다. 학생만 기록한다(도감은 학생 전용).
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
