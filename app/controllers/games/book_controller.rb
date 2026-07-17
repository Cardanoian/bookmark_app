module Games
  # 책 소개 대결(교육 다양성 5종 중 소셜 도메인). 퀴즈 파이프라인 **밖** — Gemini/Quiz 를 만들지 않는다.
  # 도서별로 학생이 소개 글을 쓰고 또래가 투표한다. 경계=학급(BookIntroPolicy 가 크로스-학급 차단).
  # AI 작성 스캐폴딩은 **정적 상수(WRITING_TIPS)** 뿐이라 문항 생성 호출이 전혀 없다(무비용).
  class BookController < BaseController
    # 소개 작성을 돕는 정적 가이드(Gemini 호출 0 — 상수). 표현용.
    WRITING_TIPS = [
      "주인공은 누구이고, 어떤 인물인가요?",
      "가장 기억에 남는 장면과 그 까닭을 적어 보세요.",
      "친구에게 이 책을 왜 추천하고 싶나요?"
    ].freeze

    # play(?book_id=) — 도서 로드 + 같은 학급 소개 목록(득표순) + 작성 폼.
    def play
      @book = Book.find(params[:book_id])
      authorize @book, :show?
      @intro = BookIntro.new
      load_intros
    end

    # create — 본인·학급으로 소개 작성. Gemini/Quiz 미생성.
    def create
      attrs = intro_params # require(:book_intro) — 없으면 400(malformed 방어)
      @book = Book.find(attrs[:book_id])
      @intro = BookIntro.new(body: attrs[:body], book: @book,
                             user: current_user, classroom: current_user.classroom)
      authorize @intro

      if @intro.save
        # 책 소개 등록 = book 게임 완료(attempts 미경유 별도 경로). game_type=book 은 라우트로 서버 확정.
        play = record_game_play!(game_type: :book, book_id: @book.id)
        discovered = play ? evaluate_monster_unlocks(current_user) : []
        redirect_to games_book_play_path(book_id: @book.id), notice: with_discovery("책 소개를 올렸어요!", discovered)
      else
        load_intros
        render :play, status: :unprocessable_entity
      end
    end

    # vote — 같은 학급 또래 소개에 1인 1표(cheer 패턴). 순차 중복(stale 탭·더블클릭)은 모델
    # 유니크 검증이 false 로 걸러 조용히 무시하고, 동시성 경쟁만 DB 유니크 인덱스가 RecordNotUnique
    # 로 잡는다(CheersController 와 동일 규약 — create! 가 아니라 create 여야 순차 중복이 422 안 됨).
    def vote
      @intro = BookIntro.find(params[:id])
      authorize @intro, :vote?

      begin
        @intro.book_intro_votes.create(user: current_user)
      rescue ActiveRecord::RecordNotUnique
        # 동시 더블클릭 경쟁 — 이미 투표한 것으로 간주(중복 카운트 없음).
      end

      redirect_to games_book_play_path(book_id: @intro.book_id)
    end

    # unvote — 본인 표 회수.
    def unvote
      @intro = BookIntro.find(params[:id])
      authorize @intro, :unvote?
      @intro.book_intro_votes.find_by(user: current_user)&.destroy
      redirect_to games_book_play_path(book_id: @intro.book_id)
    end

    private

    # 소개 목록 + 작성 가이드 로드(play·create 재렌더 공용). N+1 방지: user 프리로드 +
    # 내가 투표한 소개 id 를 1쿼리로 모아 뷰가 per-row exists? 를 돌지 않게 한다.
    def load_intros
      @intros = policy_scope(BookIntro).for_classroom(@book, current_user.classroom).ranked.includes(:user)
      @voted_ids = BookIntroVote.where(user: current_user, book_intro_id: @intros.map(&:id))
                                .pluck(:book_intro_id).to_set
      @tips = WRITING_TIPS
    end

    def intro_params
      params.require(:book_intro).permit(:body, :book_id)
    end
  end
end
