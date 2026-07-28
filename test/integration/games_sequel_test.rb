require "test_helper"

# 뒷이야기 이어쓰기(sequel) — 게임 재구성 Phase 2의 창작 소셜 도메인(book 미러). 창작 작성·또래 1인 1공감·
# 자기 글 공감 불가·**크로스-학급 차단**을 검증하고, 제출 시 game_plays(sequel) 원장 + 미션/몬스터 재평가 +
# SequelFeedbackJob(AI 코멘트 비동기) 큐잉을 확인한다. AI 코멘트는 작성자 본인에게만 노출된다.
class GamesSequelTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @school = School.create!(name: "뒷이야기게임초")
    @room_a = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @room_b = Classroom.create!(school: @school, grade: 5, class_no: 2)
    @student_a = User.create!(school: @school, classroom: @room_a, name: "뒷이야기학생A", password: "password")
    @peer = User.create!(school: @school, classroom: @room_a, name: "같은반친구", password: "password")
    @outsider = User.create!(school: @school, classroom: @room_b, name: "다른반학생", password: "password")
    @book = Book.create!(title: "뒷이야기게임책", author: "지은이", category: :recommended)
  end

  # ── 라우트 존재 ────────────────────────────────────────────────────────────
  test "sequel play, entries and vote routes are wired" do
    assert_equal "/games/sequel/play", games_sequel_play_path
    assert_equal "/games/sequel/entries", games_sequel_entries_path
    assert_equal "/games/sequel/entries/7/vote", games_sequel_vote_path(7)
  end

  # ── 작성 → 목록 노출 + 게임 완료 원장 + AI 코멘트 잡 큐잉 + Claude/Quiz 미생성 ─────
  test "creating a sequel records a game_play, enqueues feedback, and lists it (no quiz/warming)" do
    login_as @student_a

    assert_no_difference -> { Quiz.count } do
      assert_no_enqueued_jobs only: GenerateGameContentJob do
        assert_enqueued_with(job: SequelFeedbackJob) do
          assert_difference -> { BookSequel.count }, 1 do
            assert_difference -> { GamePlay.where(game_type: :sequel).count }, 1 do
              post games_sequel_entries_path, params: { book_sequel: { book_id: @book.id, body: "책이 끝난 뒤 주인공은 새로운 모험을 떠났어요." } }
            end
          end
        end
      end
    end
    assert_redirected_to games_sequel_play_path(book_id: @book.id)

    play = GamePlay.where(game_type: :sequel).last
    assert_equal @book.id, play.book_id, "sequel 게임 완료 원장은 그 책으로 기록된다"

    follow_redirect!
    assert_response :success
    assert_includes response.body, "책이 끝난 뒤 주인공은 새로운 모험을 떠났어요."
  end

  test "play page itself creates no quiz and enqueues no warming job" do
    login_as @student_a
    assert_no_difference -> { Quiz.count } do
      assert_no_enqueued_jobs only: GenerateGameContentJob do
        get games_sequel_play_path(book_id: @book.id)
      end
    end
    assert_response :success
    assert_select "h1", /뒷이야기 이어쓰기/
    assert_select "img[src*='empty_states/sequel-writing'][alt=''][width='128'][height='128']", count: 1
  end

  test "a too-short sequel is rejected with a validation message" do
    login_as @student_a
    assert_no_difference -> { BookSequel.count } do
      post games_sequel_entries_path, params: { book_sequel: { book_id: @book.id, body: "짧음" } }
    end
    assert_response :unprocessable_entity
  end

  test "a malformed create without the book_sequel key is a clean 400, not a 500" do
    login_as @student_a
    assert_no_difference -> { BookSequel.count } do
      post games_sequel_entries_path, params: { wrong_key: { body: "x" } }
    end
    assert_response :bad_request
  end

  # ── 또래 공감 1인 1표(cheer 패턴) ─────────────────────────────────────────
  test "a peer can cheer once and a double cheer is idempotent (one vote per sequel)" do
    sequel = create_sequel(@student_a)

    login_as @peer
    assert_difference -> { BookSequelVote.count }, 1 do
      post games_sequel_vote_path(sequel)
    end
    assert_equal 1, sequel.reload.votes_count

    assert_no_difference -> { BookSequelVote.count } do
      post games_sequel_vote_path(sequel)
    end
    assert_redirected_to games_sequel_play_path(book_id: sequel.book_id)
    assert_equal 1, sequel.reload.votes_count
  end

  test "a peer can retract their cheer (unvote)" do
    sequel = create_sequel(@student_a)
    login_as @peer
    post games_sequel_vote_path(sequel)
    assert_equal 1, sequel.reload.votes_count

    assert_difference -> { BookSequelVote.count }, -1 do
      delete games_sequel_vote_path(sequel)
    end
    assert_equal 0, sequel.reload.votes_count
  end

  # ── 자기 글 공감 불가 ─────────────────────────────────────────────────────
  test "a student cannot cheer their own sequel" do
    sequel = create_sequel(@student_a)
    login_as @student_a
    assert_no_difference -> { BookSequelVote.count } do
      post games_sequel_vote_path(sequel)
    end
    assert_response :forbidden
  end

  # ── 크로스-학급 차단 ──────────────────────────────────────────────────────
  test "an outsider classroom student does not see the sequel on their play page" do
    create_sequel(@student_a, body: "우리 반에만 보이는 뒷이야기예요 정말로.")

    login_as @outsider
    get games_sequel_play_path(book_id: @book.id)
    assert_response :success
    refute_includes response.body, "우리 반에만 보이는 뒷이야기예요 정말로."
  end

  test "an outsider classroom student cannot cheer another classroom's sequel" do
    sequel = create_sequel(@student_a)
    login_as @outsider
    assert_no_difference -> { BookSequelVote.count } do
      post games_sequel_vote_path(sequel)
    end
    assert_response :forbidden
  end

  # ── AI 코멘트 노출: 작성자 본인에게만 ──────────────────────────────────────
  test "the AI comment is shown to its author but hidden from classmates" do
    sequel = create_sequel(@student_a, body: "주인공이 다시 만난 이야기를 상상했어요.")
    sequel.update!(ai_status: :done, ai_comment: "상상력이 반짝이는 뒷이야기예요!")

    login_as @student_a
    get games_sequel_play_path(book_id: @book.id)
    assert_includes response.body, "상상력이 반짝이는 뒷이야기예요!", "작성자는 자기 글의 AI 코멘트를 본다"

    login_as @peer
    get games_sequel_play_path(book_id: @book.id)
    assert_includes response.body, "주인공이 다시 만난 이야기를 상상했어요.", "친구는 본문은 본다"
    refute_includes response.body, "상상력이 반짝이는 뒷이야기예요!", "친구는 남의 AI 코멘트를 보지 않는다"
  end

  test "a pending AI comment shows a reading-in-progress note to the author" do
    create_sequel(@student_a, body: "아직 코멘트가 없는 뒷이야기예요.")
    login_as @student_a
    get games_sequel_play_path(book_id: @book.id)
    assert_includes response.body, "읽는 중"
  end

  # ── 도달성: quiz·whoami·book·sequel 4종 플레이 시 distinct_games == 4 ────────
  test "playing all four active game types reaches distinct_games == 4" do
    today = Date.new(2026, 6, 1)
    %i[quiz whoami book sequel].each do |game_type|
      @student_a.game_plays.create!(game_type: game_type, book: @book, played_on: today)
    end
    assert_equal 4, ReadingStats.new(@student_a).distinct_games
  end

  private

  def create_sequel(user, body: "이 책 뒤에 이어질 이야기를 상상해서 적어요.")
    BookSequel.create!(user: user, book: @book, classroom: user.classroom, body: body)
  end
end
