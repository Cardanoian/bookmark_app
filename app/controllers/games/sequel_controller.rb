module Games
  # 뒷이야기 이어쓰기(게임 재구성 Phase 2의 창작 소셜 도메인). 책이 끝난 뒤 이어질 이야기를 학생이
  # 창작하고 또래가 공감(👍)한다. 경계=학급(BookSequelPolicy 가 크로스-학급 차단). book_controller 미러.
  # **콘텐츠 소스가 학생 상상이라 모든 책에서 항상 가능**(본문 불필요, 가용성 게이트 대상 아님).
  # 제출하면 SequelFeedbackJob 이 학생 글을 평가한 격려형 AI 코멘트를 비동기로 단다(정직한 AI).
  class SequelController < BaseController
    # 창작을 돕는 정적 가이드(Claude 호출 0 — 상수, 상상 유도). 표현용.
    WRITING_TIPS = [
      "책이 끝난 뒤, 주인공에게 어떤 일이 생길지 상상해 보세요.",
      "새로운 인물이나 사건을 등장시켜도 좋아요.",
      "이야기를 어떻게 마무리하고 싶은지 그려 보세요."
    ].freeze

    # play(?book_id=) — 도서 로드 + 같은 학급 뒷이야기 목록(득표순) + 작성 폼 + 정적 작성 가이드.
    def play
      @book = Book.find(params[:book_id])
      authorize @book, :show?
      @sequel = BookSequel.new
      load_sequels
    end

    # create — 본인·학급으로 뒷이야기 작성. 저장 성공 시 게임 완료 원장 + 미션·몬스터 재평가 +
    # AI 코멘트 비동기 큐잉. Claude/Quiz 미생성(창작 소셜 도메인).
    def create
      attrs = sequel_params # require(:book_sequel) — 없으면 400(malformed 방어)
      @book = Book.find(attrs[:book_id])
      @sequel = BookSequel.new(body: attrs[:body], book: @book,
                               user: current_user, classroom: current_user.classroom)
      authorize @sequel

      if @sequel.save
        # 뒷이야기 등록 = sequel 게임 완료(라우트로 game_type 서버 확정, book 처럼).
        play = record_game_play!(game_type: :sequel, book_id: @book.id)
        # 신규 GamePlay 일 때만 미션 진행 평가(몬스터 해금 앞).
        Missions::EvaluateProgress.new(current_user).on_game_play(play) if play
        Challenges::EvaluateProgress.new(current_user).on_game_play(play) if play
        discovered = play ? evaluate_monster_unlocks(current_user) : []
        # AI 격려 코멘트는 비동기(무대기). 무API 폴백이라 항상 코멘트가 달린다.
        SequelFeedbackJob.perform_later(@sequel.id)
        redirect_to games_sequel_play_path(book_id: @book.id),
                    notice: with_discovery("뒷이야기를 올렸어요! 책갈피 도우미가 곧 코멘트를 달아 줄 거예요.", discovered)
      else
        load_sequels
        render :play, status: :unprocessable_entity
      end
    end

    # vote — 같은 학급 또래 뒷이야기에 1인 1표(cheer 패턴). 순차 중복은 모델 유니크 검증이 조용히
    # 무시하고, 동시성 경쟁만 DB 유니크 인덱스가 RecordNotUnique 로 잡는다(book_controller 규약과 동일).
    def vote
      @sequel = BookSequel.find(params[:id])
      authorize @sequel, :vote?

      begin
        @sequel.book_sequel_votes.create(user: current_user)
      rescue ActiveRecord::RecordNotUnique
        # 동시 더블클릭 경쟁 — 이미 공감한 것으로 간주(중복 카운트 없음).
      end

      redirect_to games_sequel_play_path(book_id: @sequel.book_id)
    end

    # unvote — 본인 공감 회수.
    def unvote
      @sequel = BookSequel.find(params[:id])
      authorize @sequel, :unvote?
      @sequel.book_sequel_votes.find_by(user: current_user)&.destroy
      redirect_to games_sequel_play_path(book_id: @sequel.book_id)
    end

    private

    # 뒷이야기 목록 + 작성 가이드 로드(play·create 재렌더 공용). N+1 방지: user 프리로드 +
    # 내가 공감한 뒷이야기 id 를 1쿼리로 모아 뷰가 per-row exists? 를 돌지 않게 한다.
    def load_sequels
      @sequels = policy_scope(BookSequel).for_classroom(@book, current_user.classroom).ranked.includes(:user)
      @voted_ids = BookSequelVote.where(user: current_user, book_sequel_id: @sequels.map(&:id))
                                 .pluck(:book_sequel_id).to_set
      @tips = WRITING_TIPS
    end

    def sequel_params
      params.require(:book_sequel).permit(:body, :book_id)
    end
  end
end
