module Games
  # 다시 뽑기(Phase 3 §3.4). 현재 온디맨드 콘텐츠를 **새 content_version**으로 재생성해 그 표면의
  # play 로 돌려보낸다(rate limit·예산 하 워밍 재적재). 포인트는 콘텐츠축 상한이 이미 봉인해
  # 재생성으로 파밍되지 않는다("포인트는 최고 기록만 반영"). 경계(band/학급)는 QuizPolicy 로 인가.
  # (콘텐츠 재생성이지 가챠·랜덤 획득이 아님 — 몬스터 획득은 별개의 노력 기반 경로.)
  class RegenerateController < BaseController
    def create
      book = Book.find(params[:book_id])
      authorize book, :show?
      surface = params[:surface].to_s

      # 가용성 게이트(Phase 4 §2c, LOW 후속): resolve_on_demand 와 같은 판정 재사용 — 비활성 책은
      # 조작된 POST 로도 오프라인 Quiz 를 물질화하지 못한다(고아 행 방지, 불변식 유지).
      return unless content_gate_allows?(book, surface)

      # 다시 뽑기 per-user 스로틀(M1): 초과 시 새 content_version 을 만들지 않고 현재 판으로 안내한다
      # (오프라인 재생성의 무제한 DB 증식 차단). 정상 빈도에서는 영향 없음.
      unless Games::ContentProvider.regenerate_allowed?(current_user)
        return redirect_to regenerate_target(surface, book),
                           alert: "다시 뽑기는 잠시 후에 다시 시도해 주세요."
      end

      quiz = Games::ContentProvider.regenerate(book: book, surface: surface, user: current_user)
      authorize quiz, :show?

      redirect_to regenerate_target(surface, book), notice: "새 문제를 뽑았어요! 포인트는 최고 기록만 반영돼요."
    end

    private

    # 표면 → 온디맨드 play 경로(허용 목록만). whoami 는 play 가 attempt 를 새로 선생성한다.
    # 게임 재구성 Phase 1: 표면은 quiz·whoami 만(classic/vocab 제거).
    def regenerate_target(surface, book)
      case surface
      when "whoami" then games_whoami_play_path(book_id: book.id)
      else games_quiz_play_path(book_id: book.id)
      end
    end
  end
end
