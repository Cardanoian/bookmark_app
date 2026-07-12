require "test_helper"

# Phase 3 §3 — 온디맨드 게임 편입 e2e(무키 오프라인). 카탈로그 진입 + 퀴즈 파이프라인 4종 표면 플레이 +
# whoami 힌트 **서버 권위**(위조·stale-cookie replay 불변) + 재롤(새 버전·포인트 0) + 정직 안내.
class GamesOndemandTest < ActionDispatch::IntegrationTest
  setup do
    seed_monster_species!
    seed_badges!
    @school = School.create!(name: "온디맨드초")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1) # g56
    @student = User.create!(school: @school, classroom: @classroom, name: "온디학생", password: "password")
    @book = Book.create!(title: "온디책", author: "김저자", summary: "모험을 떠난 소년의 긴 여정 이야기.", category: :recommended)
    login_as @student
  end

  # ── 카탈로그 진입 ─────────────────────────────────────────────────────
  test "catalog lists playable games and books, linking to on-demand play" do
    get games_catalog_path
    assert_response :success
    assert_includes response.body, "독서 퀴즈"
    assert_includes response.body, "어휘 낚시"
    assert_select "a[href=?]", games_whoami_play_path(book_id: @book.id)
  end

  # ── 퀴즈 파이프라인 4종 표면 오프라인 e2e(미스=오프라인 즉시, 아동 무대기) ────────────
  %w[quiz classic vocab].each do |surface|
    test "#{surface} on-demand play renders an offline system quiz immediately" do
      get public_send("games_#{surface}_play_path", book_id: @book.id)
      assert_response :success

      quiz = Quiz.where(origin: :system, book_id: @book.id).order(:id).last
      assert_equal "ready", quiz.generation_status
      assert_equal "offline", quiz.quiz_questions.first.source, "미스는 결정적 오프라인 즉시 제공"
    end
  end

  test "whoami on-demand play pre-creates an attempt and redirects to the attempt-keyed show" do
    get games_whoami_play_path(book_id: @book.id)
    attempt = @student.quiz_attempts.order(:id).last
    assert_not_nil attempt, "whoami 는 시작 시 attempt 를 선생성한다(reveal_hint 가 :attempt 요구)"
    assert_redirected_to games_whoami_path(attempt)

    follow_redirect!
    assert_response :success
    assert_select "h1", /나는 누구게/
  end

  # ── mcq 온디맨드 채점 → QuizAttempt + 포인트(정직 안내 유지) ───────────────
  test "playing an on-demand mcq awards points and honest notice, then re-play awards zero" do
    get games_quiz_play_path(book_id: @book.id)
    quiz = Quiz.where(origin: :system, book_id: @book.id, content_axis: :mcq).last

    play_all_correct(quiz, "quiz")
    assert_operator @student.reload.points, :>, 0, "첫 만점은 전액 적립"
    assert_match "얻었어요", flash[:notice]

    best = @student.points
    play_all_correct(quiz, "quiz")
    assert_equal best, @student.reload.points, "온디맨드 재플레이는 콘텐츠축 상한으로 +0"
    assert_match "추가 포인트는 없어요", flash[:notice]
    refute_match "얻었어요", flash[:notice]
  end

  # ── matching 온디맨드 채점(쌍맵 무유출·선택 인덱스만 전송) ──────────────────
  test "vocab matching does not leak the pair-map and scores chosen indices server-side" do
    get games_vocab_play_path(book_id: @book.id)
    assert_response :success
    quiz = Quiz.where(origin: :system, book_id: @book.id, content_axis: :matching).last
    question = quiz.quiz_questions.first

    # 정답 쌍맵(answer)이 마크업에 직렬화되면 안 된다(무유출).
    assert_not_includes response.body, "answers[#{question.id}][0]\" value", "정답 인덱스가 프리필되면 안 된다"

    # 정답 쌍맵대로 제출 → 전부 매칭.
    post games_attempts_path, params: { quiz_id: quiz.id, game: "vocab", answers: { question.id.to_s => question.answer } }
    attempt = QuizAttempt.where(quiz: quiz).last
    assert_equal question.answer.size * Games::QuestionScorer::POINTS_PER_CORRECT, attempt.points_awarded
  end

  # ── C1 whoami 힌트 서버 권위 — 위조/stale-cookie replay 로도 점수 불변 ───────
  test "whoami hint count is server-authoritative — revealing hints lowers the server-scored points" do
    quiz, attempt = start_whoami
    q1 = quiz.quiz_questions.first

    # q1 힌트 2개 공개(서버 카운터 = 2, DB 에 저장).
    2.times { reveal_hint(attempt, q1) }
    assert_equal 2, attempt.reload.revealed_count(q1), "힌트 공개수는 서버(attempt.hint_reveals, DB)에 누적된다"

    submit_whoami_all_correct(quiz, attempt)
    finalized = attempt.reload
    # q1: 정답이지만 힌트 2개 차감 → max(5-2,1)=3, q2·q3: 5점씩. 만점(15)이 아니라 13.
    expected = (Games::QuestionScorer::POINTS_PER_CORRECT - 2) + 2 * Games::QuestionScorer::POINTS_PER_CORRECT
    assert_equal expected, finalized.points_awarded, "서버 힌트 카운트만큼 차감된 점수"
    assert_equal 3, finalized.score
  end

  test "a forged/stale client hint count cannot lower the penalty (C1 replay guard)" do
    quiz, attempt = start_whoami
    q1 = quiz.quiz_questions.first
    2.times { reveal_hint(attempt, q1) } # 서버 카운터 = 2

    # 클라이언트가 "힌트 0개 봤다"고 위조(=구 쿠키 replay 시나리오)해도 서버 카운트(DB)가 권위.
    answers = correct_answers(quiz)
    post games_attempts_path, params: {
      quiz_id: quiz.id, game: "whoami", attempt_id: attempt.id, answers: answers,
      hints_used: 0, hint_reveals: { q1.id.to_s => 0 } # 위조 파라미터 — 서버가 무시해야 한다
    }

    forged_score = attempt.reload.points_awarded
    honest = (Games::QuestionScorer::POINTS_PER_CORRECT - 2) + 2 * Games::QuestionScorer::POINTS_PER_CORRECT
    assert_equal honest, forged_score, "위조/stale 힌트수를 보내도 서버 DB 카운트 기준이라 점수가 바뀌지 않는다"
    refute_equal 3 * Games::QuestionScorer::POINTS_PER_CORRECT, forged_score, "위조로 만점을 받을 수 없다"
  end

  # H1: attempt_id 를 **생략**하면 hints_used=0 인 새 attempt 로 채점돼 힌트 페널티를 우회할 수 있었다.
  # 이제 hint_reveal 제출은 선생성 attempt 를 강제(없으면 거부) + server_hints_used fail-safe 로 이중 차단한다.
  test "omitting attempt_id on a whoami submit cannot bypass the hint penalty (H1)" do
    quiz, attempt = start_whoami
    q1 = quiz.quiz_questions.first
    2.times { reveal_hint(attempt, q1) } # 서버 카운터 = 2

    max_award = 3 * Games::QuestionScorer::POINTS_PER_CORRECT
    post games_attempts_path, params: {
      quiz_id: quiz.id, game: "whoami", answers: correct_answers(quiz) # attempt_id 생략(우회 시도)
    }

    assert_redirected_to games_whoami_play_path(book_id: quiz.book_id), "선생성 attempt 없는 hint_reveal 제출은 거부·재시작"
    refute @student.quiz_attempts.where("points_awarded >= ?", max_award).exists?,
           "attempt_id 를 빼고 제출해도 힌트 페널티를 우회해 만점받을 수 없다(H1)"
  end

  # 제출 후 결과 안내(flash)가 새 판 show 까지 살아남는다(play→show 이중 리다이렉트에도 keep).
  test "whoami result notice survives to the fresh game page after submit" do
    quiz, attempt = start_whoami
    submit_whoami_all_correct(quiz, attempt)
    follow_redirect! # attempts → whoami play
    follow_redirect! # play → show
    assert_response :success
    assert_match "정답", flash[:notice]
  end

  # ── 재롤(§3.4): 새 content_version, 추가 포인트 0 ─────────────────────────
  test "re-roll makes a new content_version and awards zero extra points" do
    get games_quiz_play_path(book_id: @book.id)
    original = Quiz.where(origin: :system, book_id: @book.id, content_axis: :mcq).last
    play_all_correct(original, "quiz")
    best = @student.reload.points
    assert_operator best, :>, 0

    post games_regenerate_path, params: { book_id: @book.id, surface: "quiz" }
    rerolled = Quiz.where(origin: :system, book_id: @book.id, content_axis: :mcq).order(:content_version).last
    assert_operator rerolled.content_version, :>, original.content_version, "재롤은 새 content_version 을 만든다"
    assert_not_equal original.id, rerolled.id
    assert_redirected_to games_quiz_play_path(book_id: @book.id)

    play_all_correct(rerolled, "quiz")
    assert_equal best, @student.reload.points, "재롤 후 만점도 콘텐츠축 상한으로 추가 포인트 0"
  end

  private

  def start_whoami
    get games_whoami_play_path(book_id: @book.id)
    attempt = @student.quiz_attempts.order(:id).last
    [ attempt.quiz, attempt ]
  end

  def reveal_hint(attempt, question)
    post games_whoami_reveal_hint_path(attempt: attempt.id), params: { question_id: question.id }
  end

  def correct_answers(quiz)
    quiz.quiz_questions.each_with_object({}) { |q, h| h[q.id.to_s] = q.answer }
  end

  def submit_whoami_all_correct(quiz, attempt)
    post games_attempts_path, params: {
      quiz_id: quiz.id, game: "whoami", attempt_id: attempt.id, answers: correct_answers(quiz)
    }
  end

  def play_all_correct(quiz, game)
    answers = quiz.quiz_questions.each_with_object({}) { |q, h| h[q.id.to_s] = q.answer_index }
    post games_attempts_path, params: { quiz_id: quiz.id, game: game, answers: answers }
  end

  def login_as(user)
    post session_path, params: {
      school_id: user.school_id, classroom_id: user.classroom_id, name: user.name, password: "password"
    }
  end
end
