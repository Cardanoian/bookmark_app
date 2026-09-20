require "test_helper"

# §1.2 퀴즈 포인트 파밍 차단 — QuizPlay#record! 의 멱등(최고점 델타) 적립을 증명한다.
# 매 제출마다 만점을 재지급하던 예전 동작 대신, 같은 퀴즈에서 이 학생의 최고 적립액을
# 초과한 만큼만 지급한다: 첫 만점 전액, 재플레이 0, 더 높은 점수는 증가분만.
class Games::QuizPlayTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "퀴즈파밍초")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @teacher = User.create!(school: @school, classroom: @classroom, name: "파밍교사", password: "password", role: :teacher)
    @student = User.create!(school: @school, classroom: @classroom, name: "파밍학생", password: "password")
    @book = Book.create!(title: "파밍책", category: :recommended)
    @quiz = build_quiz("파밍 퀴즈")
  end

  test "first perfect play awards the full amount and records points_awarded on the attempt" do
    attempt = play(all_correct)

    assert_equal 5, attempt.score
    assert_equal 25, attempt.points_awarded, "이번 판 점수 기반 적립액을 기록한다"
    assert_equal 25, @student.reload.points, "첫 만점은 전액 적립"
  end

  test "replaying the same quiz all-correct awards points only once" do
    play(all_correct)
    assert_equal 25, @student.reload.points

    second = play(all_correct)
    assert_equal 25, second.points_awarded, "재플레이 attempt 도 자기 점수를 기록한다"
    assert_equal 25, @student.reload.points, "재플레이 delta 는 0 — 포인트가 늘지 않는다"
    assert_equal 2, @quiz.quiz_attempts.where(user: @student).count, "플레이 기록 자체는 남는다"
  end

  test "a higher later score awards only the incremental delta over the best prior score" do
    play(one_correct) # 1문항 정답 → 5점
    assert_equal 5, @student.reload.points

    play(all_correct) # 만점 25점 → 이전 최고 5점 대비 delta 20
    assert_equal 25, @student.reload.points, "최고점 대비 증가분(20)만 추가 적립"
  end

  test "a lower later score awards nothing" do
    play(all_correct) # 25점
    assert_equal 25, @student.reload.points

    play(one_correct) # 5점 (최고 25점 미만) → delta 0
    assert_equal 25, @student.reload.points, "최고점보다 낮은 점수는 추가 적립 없음"
  end

  test "zero correct never awards points" do
    attempt = play(all_wrong)

    assert_equal 0, attempt.score
    assert_equal 0, attempt.points_awarded
    assert_equal 0, @student.reload.points
  end

  # ── F1(BUG_FIX_PLAN §3.2·§3.3): 완료된 attempt 는 다시 확정되지 않는다 ─────────────────────
  test "re-sending a finalized whoami attempt with the same answers changes nothing" do
    quiz, attempt = start_whoami
    first = play_whoami(quiz, attempt, whoami_correct(quiz))
    assert first.newly_finalized?
    assert_equal 15, first.awarded_delta
    assert_not_nil first.game_play
    snapshot = finalized_snapshot(attempt)

    assert_no_difference [ -> { GamePlay.count }, -> { QuizAttempt.count } ] do
      replay = play_whoami(quiz, attempt, whoami_correct(quiz))
      assert_not replay.newly_finalized?, "같은 attempt 의 재전송은 새 판이 아니다"
      assert_equal 0, replay.awarded_delta
      assert_nil replay.game_play
      assert_equal 3, replay.score, "저장된 결과를 그대로 돌려준다"
    end

    assert_equal snapshot, finalized_snapshot(attempt)
    assert_reward_totals 15
  end

  test "re-sending a finalized whoami attempt with different answers cannot rewrite it" do
    quiz, attempt = start_whoami
    play_whoami(quiz, attempt, whoami_wrong(quiz)) # 0점으로 확정
    snapshot = finalized_snapshot(attempt)
    assert_equal 0, attempt.reload.points_awarded

    replay = play_whoami(quiz, attempt, whoami_correct(quiz)) # 같은 attempt 에 정답을 다시 보낸다
    assert_not replay.newly_finalized?
    assert_equal 0, replay.awarded_delta, "확정한 뒤 답을 바꿔 보내도 보상이 생기지 않는다"
    assert_equal 0, replay.score

    assert_equal snapshot, finalized_snapshot(attempt), "답안·점수·완료 시각이 바뀌지 않는다"
    assert_reward_totals 0
  end

  # 새 판(새 attempt)에서 기록을 개선하면 차액만, 개선하지 못해도 활동 완료로는 기록될 수 있다.
  test "a fresh whoami attempt is a new play: delta over the best, and zero delta still counts as a play" do
    quiz, first_attempt = start_whoami
    first_attempt.update!(hint_reveals: { quiz.quiz_questions.first.id.to_s => 2 }) # 힌트 2개 → 13점
    assert_equal 13, play_whoami(quiz, first_attempt, whoami_correct(quiz)).awarded_delta

    travel_to 1.day.from_now do
      second = play_whoami(quiz, new_attempt(quiz), whoami_correct(quiz)) # 힌트 없이 만점 15점
      assert second.newly_finalized?
      assert_equal 2, second.awarded_delta, "최고점 대비 차액만"
      assert_not_nil second.game_play, "다음 날의 새 판은 새 완료 기록"
    end

    travel_to 2.days.from_now do
      third = play_whoami(quiz, new_attempt(quiz), whoami_wrong(quiz))
      assert third.newly_finalized?, "추가 포인트가 0 이어도 정상 새 판이다"
      assert_equal 0, third.awarded_delta
      assert_not_nil third.game_play, "추가 포인트 0 인 새 판도 활동 완료로 기록된다"
    end
    assert_reward_totals 15
  end

  # 중복 요청이 날짜를 넘어 도착해도 다음 날의 새 게임 완료로 기록하지 않는다.
  test "a finalized attempt re-sent the next day records no new completion" do
    quiz, attempt = start_whoami
    play_whoami(quiz, attempt, whoami_correct(quiz))

    travel_to 1.day.from_now do
      assert_no_difference -> { GamePlay.count } do
        replay = play_whoami(quiz, attempt, whoami_correct(quiz))
        assert_not replay.newly_finalized?
        assert_nil replay.game_play
      end
    end
    assert_reward_totals 15
  end

  # 같은 날 이미 있는 완료 행과 부딪혀도(일일 유니크) attempt 확정과 적립은 그대로 남는다.
  test "a same-day ledger collision keeps the finalize and the credit" do
    quiz, attempt = start_whoami
    GamePlay.record_daily!(user: @student, game_type: :whoami, book_id: @book.id)

    result = play_whoami(quiz, attempt, whoami_correct(quiz))

    assert result.newly_finalized?
    assert_nil result.game_play, "같은 날 같은 게임·책의 완료 행이 이미 있다"
    assert attempt.reload.finalized?
    assert_equal 15, attempt.points_awarded
    assert_reward_totals 15
    assert_equal 1, @student.game_plays.count
  end

  # 서버가 정한 종류로만 기록한다(F4) — 객관식은 quiz, hint_reveal 은 whoami.
  test "the ledger row uses the server-decided game type" do
    assert_equal "quiz", play(all_correct).game_play.game_type

    quiz, attempt = start_whoami
    assert_equal "whoami", play_whoami(quiz, attempt, whoami_correct(quiz)).game_play.game_type
  end

  test "an attempt that belongs to another student or quiz is refused" do
    quiz, = start_whoami
    other = User.create!(school: @school, classroom: @classroom, name: "다른학생", password: "password")
    foreign = quiz.quiz_attempts.create!(user: other, hint_reveals: {}, score: 0, points_awarded: 0)
    other_quiz_attempt = @quiz.quiz_attempts.create!(user: @student, score: 0, points_awarded: 0)

    assert_raises(ArgumentError) { Games::QuizPlay.new(quiz: quiz, user: @student, attempt: foreign) }
    assert_raises(ArgumentError) { Games::QuizPlay.new(quiz: quiz, user: @student, attempt: other_quiz_attempt) }
  end

  private

  def start_whoami
    quiz = Quiz.create!(title: "누구게 #{SecureRandom.hex(3)}", created_by: @teacher, book: @book, scope: :global,
                        published: true, origin: :system, content_axis: :hint_reveal, band: :g56, content_version: 1)
    3.times do |i|
      quiz.quiz_questions.create!(question_type: :hint_reveal, prompt: "누구게#{i}", answer: "정답#{i}",
                                  content: { hints: %w[힌트1 힌트2] }, position: i + 1)
    end
    [ quiz, new_attempt(quiz) ]
  end

  def new_attempt(quiz)
    quiz.quiz_attempts.create!(user: @student, hint_reveals: {}, score: 0, points_awarded: 0)
  end

  def play_whoami(quiz, attempt, answers)
    Games::QuizPlay.new(quiz: quiz, user: @student, attempt: QuizAttempt.find(attempt.id)).record!(answers)
  end

  def whoami_correct(quiz)
    quiz.quiz_questions.each_with_object({}) { |q, h| h[q.id.to_s] = q.answer }
  end

  def whoami_wrong(quiz)
    quiz.quiz_questions.each_with_object({}) { |q, h| h[q.id.to_s] = "틀린답" }
  end

  def finalized_snapshot(attempt)
    attempt.reload.attributes.slice("score", "answers", "points_awarded", "played_at", "hint_reveals")
  end

  # 포인트·경험치·시즌 점수가 함께 움직인다(같은 트랜잭션에서 반영).
  def assert_reward_totals(expected)
    @student.reload
    assert_equal expected, @student.points
    assert_equal expected, @student.experience
    season = SeasonScore.find_by(user: @student, academic_year: Classroom.current_academic_year)
    assert_equal expected, season&.experience_earned.to_i
    assert_equal expected, season&.points_earned.to_i
  end

  def play(answers)
    Games::QuizPlay.new(quiz: @quiz, user: @student).record!(answers)
  end

  def all_correct
    @quiz.quiz_questions.each_with_object({}) { |q, h| h[q.id.to_s] = q.answer_index }
  end

  # 첫 문항만 정답, 나머지는 오답.
  def one_correct
    @quiz.quiz_questions.order(:position).each_with_object({}).with_index do |(q, h), i|
      h[q.id.to_s] = i.zero? ? q.answer_index : (q.answer_index + 1)
    end
  end

  # 모든 문항 오답(정답 인덱스와 다른 값). 미응답은 nil.to_i==0 이 answer_index 0 과
  # 일치해 오히려 정답 처리되므로, 확실한 오답 인덱스를 명시한다.
  def all_wrong
    @quiz.quiz_questions.each_with_object({}) { |q, h| h[q.id.to_s] = q.answer_index + 1 }
  end

  def build_quiz(title)
    quiz = Quiz.create!(title: title, created_by: @teacher, book: @book, scope: :global, published: true)
    5.times do |i|
      quiz.quiz_questions.create!(prompt: "문제#{i}", choices: %w[정답 오답1 오답2 오답3], answer_index: 0, position: i + 1)
    end
    quiz
  end
end
