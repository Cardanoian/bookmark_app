require "test_helper"

# 책 소개 대결(book) — 교육 다양성 5종의 소셜 도메인. 퀴즈 파이프라인 **밖**이라 Claude/Quiz 를
# 만들지 않는다(assert). 소개 작성·또래 1인 1표·자기 소개 투표 불가·**크로스-학급 차단**을 검증한다.
class GamesBookIntroTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @school = School.create!(name: "소개초")
    @room_a = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @room_b = Classroom.create!(school: @school, grade: 5, class_no: 2)
    @student_a = User.create!(school: @school, classroom: @room_a, name: "소개학생A", password: "password")
    @peer = User.create!(school: @school, classroom: @room_a, name: "같은반친구", password: "password")
    @outsider = User.create!(school: @school, classroom: @room_b, name: "다른반학생", password: "password")
    @book = Book.create!(title: "소개책", author: "지은이", category: :recommended)
  end

  # ── 소개 작성 → 목록 노출 + Claude/Quiz 미생성 ─────────────────────────────
  test "creating an intro lists it on the play page without any quiz or warming job" do
    login_as @student_a

    assert_no_difference -> { Quiz.count } do
      assert_no_enqueued_jobs only: GenerateGameContentJob do
        assert_difference -> { BookIntro.count }, 1 do
          post games_book_intros_path, params: { book_intro: { book_id: @book.id, body: "이 책은 정말 감동적이라 꼭 추천해요." } }
        end
      end
    end
    assert_redirected_to games_book_play_path(book_id: @book.id)

    follow_redirect!
    assert_response :success
    assert_includes response.body, "이 책은 정말 감동적이라 꼭 추천해요."
  end

  test "play page itself creates no quiz and enqueues no warming job (not the quiz pipeline)" do
    login_as @student_a
    assert_no_difference -> { Quiz.count } do
      assert_no_enqueued_jobs only: GenerateGameContentJob do
        get games_book_play_path(book_id: @book.id)
      end
    end
    assert_response :success
    assert_select "h1", /책 소개 대결/
    assert_select "img[src*='empty_states/sequel-writing'][alt=''][width='128'][height='128']", count: 1
  end

  test "a too-short intro is rejected with a validation message" do
    login_as @student_a
    assert_no_difference -> { BookIntro.count } do
      post games_book_intros_path, params: { book_intro: { book_id: @book.id, body: "짧음" } }
    end
    assert_response :unprocessable_entity
  end

  test "a malformed create without the book_intro key is a clean 400, not a 500" do
    login_as @student_a
    assert_no_difference -> { BookIntro.count } do
      post games_book_intros_path, params: { wrong_key: { body: "x" } }
    end
    assert_response :bad_request, "book_intro 파라미터 누락은 require 가 400 으로 막는다(500 아님)"
  end

  # ── 또래 투표 1인 1표(cheer 패턴) ─────────────────────────────────────────
  test "a peer can vote once and a double vote is idempotent (one vote per intro)" do
    intro = create_intro(@student_a)

    login_as @peer
    assert_difference -> { BookIntroVote.count }, 1 do
      post games_book_vote_path(intro)
    end
    assert_equal 1, intro.reload.votes_count

    # 두 번째(순차) 투표는 모델 유니크 검증이 조용히 무시(중복 카운트 없음) — 422 아님, 정상 리다이렉트.
    assert_no_difference -> { BookIntroVote.count } do
      post games_book_vote_path(intro)
    end
    assert_redirected_to games_book_play_path(book_id: intro.book_id), "순차 중복 투표는 422 없이 게임으로 복귀"
    assert_equal 1, intro.reload.votes_count
  end

  test "a peer can retract their vote (unvote)" do
    intro = create_intro(@student_a)
    login_as @peer
    post games_book_vote_path(intro)
    assert_equal 1, intro.reload.votes_count

    assert_difference -> { BookIntroVote.count }, -1 do
      delete games_book_vote_path(intro)
    end
    assert_equal 0, intro.reload.votes_count
  end

  # ── 자기 소개 투표 불가(대결 공정성) ─────────────────────────────────────
  test "a student cannot vote on their own intro" do
    intro = create_intro(@student_a)
    login_as @student_a
    assert_no_difference -> { BookIntroVote.count } do
      post games_book_vote_path(intro)
    end
    assert_response :forbidden
  end

  # ── 크로스-학급 차단: 타 학급 학생은 소개 열람·투표 불가 ──────────────────
  test "an outsider classroom student does not see the intro on their play page" do
    create_intro(@student_a, body: "우리 반에만 보이는 소개예요 정말로.")

    login_as @outsider
    get games_book_play_path(book_id: @book.id)
    assert_response :success
    refute_includes response.body, "우리 반에만 보이는 소개예요 정말로.", "타 학급 소개는 스코프에서 배제된다"
  end

  test "an outsider classroom student cannot vote on another classroom's intro" do
    intro = create_intro(@student_a)
    login_as @outsider
    assert_no_difference -> { BookIntroVote.count } do
      post games_book_vote_path(intro)
    end
    assert_response :forbidden, "크로스-학급 투표는 정책이 차단한다"
  end

  private

  def create_intro(user, body: "이 책을 친구에게 추천하고 싶은 이유를 적어요.")
    BookIntro.create!(user: user, book: @book, classroom: user.classroom, body: body)
  end
end
