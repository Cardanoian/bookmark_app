require "test_helper"

# 게임 제출 보상의 **병렬** 검증(BUG_FIX_PLAN F1 §3.2·§6). 서로 다른 DB 연결(스레드)에서 같은 attempt 를
# 동시에 제출하거나, 같은 보상 범위의 서로 다른 attempt 를 동시에 제출해도 확정·적립이 정확히 한 번(최고점
# 기준)인지 본다. 순차 테스트로는 "읽고 나서 쓰기" 사이의 경합을 못 잡는다. 스레드가 서로의 커밋을 봐야
# 하므로 트랜잭션 픽스처를 끈다(mission_reward_concurrency_test 선례) — 같은 이유로 트랜잭션 **롤백**도
# 여기서 본다(픽스처 트랜잭션 안에서는 안쪽 transaction 이 바깥에 합류해 롤백되지 않는다).
class GameRewardConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @school = School.create!(name: "게임동시초")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @teacher = User.create!(school: @school, classroom: @classroom, name: "게임동시교사", password: "password", role: :teacher)
    @student = User.create!(school: @school, classroom: @classroom, name: "게임동시생", password: "password", points: 0)
    @book = Book.create!(title: "게임동시책", category: :recommended)
  end

  teardown do
    quiz_ids = Quiz.where(book_id: @book&.id).pluck(:id)
    QuizAttempt.where(quiz_id: quiz_ids).delete_all
    QuizQuestion.where(quiz_id: quiz_ids).delete_all
    Quiz.where(id: quiz_ids).delete_all
    GamePlay.where(user_id: @student&.id).delete_all
    SeasonScore.where(user_id: @student&.id).delete_all
    UserBadge.where(user_id: @student&.id).delete_all
    User.where(school_id: @school&.id).delete_all
    Classroom.where(school_id: @school&.id).delete_all
    School.where(id: @school&.id).delete_all
    Book.where(id: @book&.id).delete_all
  end

  test "같은 whoami attempt 를 두 연결이 동시에 제출해도 확정과 보상은 한 번이다" do
    quiz = whoami_quiz
    attempt = quiz.quiz_attempts.create!(user: @student, hint_reveals: {}, score: 0, points_awarded: 0)
    answers = quiz.quiz_questions.each_with_object({}) { |q, h| h[q.id.to_s] = q.answer }

    results = in_parallel(2) do
      Games::QuizPlay.new(quiz: Quiz.find(quiz.id), user: User.find(@student.id),
                          attempt: QuizAttempt.find(attempt.id)).record!(answers)
    end

    assert_equal [ false, true ], results.map(&:newly_finalized?).sort_by { |v| v ? 1 : 0 }, "확정은 한 요청만"
    assert_equal 15, results.sum(&:awarded_delta)
    assert_equal 15, @student.reload.points, "정확히 1회분만 적립"
    assert_equal 15, @student.experience
    assert_equal 1, @student.game_plays.count
    assert_equal 1, quiz.quiz_attempts.where(user: @student).count
  end

  test "같은 보상 범위의 서로 다른 attempt 를 동시에 저장해도 최고점만큼만 지급된다" do
    quiz = mcq_quiz
    perfect = quiz.quiz_questions.each_with_object({}) { |q, h| h[q.id.to_s] = q.answer_index }
    one_right = quiz.quiz_questions.each_with_object({}).with_index do |(q, h), i|
      h[q.id.to_s] = i.zero? ? q.answer_index : q.answer_index + 1
    end

    results = in_parallel(3) do |i|
      answers = i == 1 ? one_right : perfect # 만점(25) 두 번 + 5점 한 번
      Games::QuizPlay.new(quiz: Quiz.find(quiz.id), user: User.find(@student.id)).record!(answers)
    end

    assert results.all?(&:newly_finalized?), "객관식은 요청마다 새 판이다"
    assert_equal 25, results.sum(&:awarded_delta), "중복 지급도 미지급도 없다"
    assert_equal 25, @student.reload.points
    assert_equal 25, @student.experience
    assert_equal 3, quiz.quiz_attempts.where(user: @student).count
    assert_equal 1, @student.game_plays.count, "완료 원장은 일일 유니크로 1행"
  end

  test "힌트 공개와 제출이 겹쳐도 확정 점수와 힌트 기록이 어긋나지 않는다" do
    quiz = whoami_quiz
    question = quiz.quiz_questions.first
    answers = quiz.quiz_questions.each_with_object({}) { |q, h| h[q.id.to_s] = q.answer }

    5.times do
      attempt = quiz.quiz_attempts.create!(user: @student, hint_reveals: {}, score: 0, points_awarded: 0)
      in_parallel(2) do |i|
        if i.zero?
          QuizAttempt.find(attempt.id).reveal_hint!(QuizQuestion.find(question.id))
        else
          Games::QuizPlay.new(quiz: Quiz.find(quiz.id), user: User.find(@student.id),
                              attempt: QuizAttempt.find(attempt.id)).record!(answers)
        end
      end

      attempt.reload
      assert attempt.finalized?
      assert_equal 15 - attempt.revealed_count(question), attempt.points_awarded,
                   "확정 점수는 기록된 힌트 공개수로 차감한 값이다"
    end
  end

  test "완료된 attempt 에는 힌트를 더 공개하지 않는다" do
    quiz = whoami_quiz
    question = quiz.quiz_questions.first
    attempt = quiz.quiz_attempts.create!(user: @student, hint_reveals: {}, score: 0, points_awarded: 0)
    assert attempt.reveal_hint!(question)
    answers = quiz.quiz_questions.each_with_object({}) { |q, h| h[q.id.to_s] = q.answer }
    Games::QuizPlay.new(quiz: quiz, user: @student, attempt: attempt).record!(answers)

    assert_not QuizAttempt.find(attempt.id).reveal_hint!(question)
    assert_equal 1, attempt.reload.revealed_count(question), "확정된 기록의 힌트 공개수는 그대로다"
    assert_equal 14, attempt.points_awarded
  end

  # 완료 원장을 같은 트랜잭션에 두는 이유: 기록 중 예외가 나면 확정·적립까지 함께 되돌려, 다시 보낸 요청이
  # 처음부터 정상 확정되게 한다(따로 커밋하면 확정만 남고 원장이 빠진 채 복구되지 않는다).
  test "완료 원장 기록 중 예외가 나면 확정·적립이 함께 롤백되고 재전송으로 정상 확정된다" do
    quiz = whoami_quiz
    attempt = quiz.quiz_attempts.create!(user: @student, hint_reveals: {}, score: 0, points_awarded: 0)
    answers = quiz.quiz_questions.each_with_object({}) { |q, h| h[q.id.to_s] = q.answer }

    # record_daily! 는 GamePlay 자신의 클래스 메서드라(상속받은 것이 아니다) 지우면 원본까지 사라진다 —
    # 원본을 잡아 두었다가 되돌린다.
    original = GamePlay.method(:record_daily!)
    GamePlay.define_singleton_method(:record_daily!) { |**| raise "ledger boom" }
    begin
      error = assert_raises(RuntimeError) do
        Games::QuizPlay.new(quiz: quiz, user: @student, attempt: QuizAttempt.find(attempt.id)).record!(answers)
      end
      assert_equal "ledger boom", error.message
    ensure
      GamePlay.define_singleton_method(:record_daily!, original)
    end

    assert_not attempt.reload.finalized?, "확정이 롤백됐다"
    assert_equal 0, @student.reload.points, "적립도 롤백됐다"
    assert_equal 0, SeasonScore.where(user_id: @student.id).sum(:points_earned)
    assert_equal 0, @student.game_plays.count

    retried = Games::QuizPlay.new(quiz: quiz, user: @student, attempt: QuizAttempt.find(attempt.id)).record!(answers)
    assert retried.newly_finalized?
    assert_equal 15, retried.awarded_delta
    assert_not_nil retried.game_play
    assert_equal 15, @student.reload.points
  end

  private

  # 블록을 n 개의 스레드(각자 DB 연결)에서 동시에 시작한다. 결과 배열을 돌려준다. 예외는 **모든 스레드가
  # 끝난 뒤에** 다시 올린다 — 먼저 올리면 남은 스레드가 teardown 이 지운 행을 찾다가 엉뚱한 오류를 낸다.
  def in_parallel(count)
    gate = Queue.new
    threads = count.times.map do |i|
      Thread.new do
        Thread.current.report_on_exception = false
        ActiveRecord::Base.connection_pool.with_connection do
          gate.pop
          yield i
        end
      rescue StandardError => e
        e
      end
    end
    count.times { gate << :go }
    results = threads.map(&:value)
    failure = results.find { |result| result.is_a?(StandardError) }
    raise failure if failure

    results
  end

  def mcq_quiz
    quiz = Quiz.create!(title: "동시 퀴즈", created_by: @teacher, book: @book, scope: :global, published: true)
    5.times do |i|
      quiz.quiz_questions.create!(prompt: "문제#{i}", choices: %w[정답 오답1 오답2 오답3], answer_index: 0, position: i + 1)
    end
    quiz
  end

  def whoami_quiz
    quiz = Quiz.create!(title: "동시 누구게", created_by: @teacher, book: @book, scope: :global, published: true,
                        origin: :system, content_axis: :hint_reveal, band: :g56, content_version: 1)
    3.times do |i|
      quiz.quiz_questions.create!(question_type: :hint_reveal, prompt: "누구게#{i}", answer: "정답#{i}",
                                  content: { hints: %w[힌트1 힌트2] }, position: i + 1)
    end
    quiz
  end
end
