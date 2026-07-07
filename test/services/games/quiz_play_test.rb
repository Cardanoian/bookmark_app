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

  private

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
