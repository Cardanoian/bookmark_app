require "test_helper"

class QuizModelsTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "퀴즈초등학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @teacher = User.create!(school: @school, classroom: @classroom, name: "퀴즈교사", password: "password", role: :teacher)
    @student = User.create!(school: @school, classroom: @classroom, name: "퀴즈학생", password: "password")
    @book = Book.create!(title: "퀴즈책", category: :recommended)
  end

  def quiz(attrs = {})
    Quiz.create!({ title: "샘플 퀴즈", created_by: @teacher, scope: :global }.merge(attrs))
  end

  test "quiz belongs to creator and optional book/classroom" do
    q = quiz(book: @book, classroom: @classroom)
    assert_equal @teacher, q.created_by
    assert_equal @book, q.book
    assert_equal @classroom, q.classroom
  end

  test "quiz requires a title" do
    assert_not Quiz.new(created_by: @teacher).valid?
  end

  test "quiz scope enum exposes classroom/global" do
    assert quiz(scope: :global).global?
    assert quiz(scope: :classroom).classroom?
  end

  test "published scope returns only published quizzes" do
    published = quiz(published: true)
    quiz(published: false)
    assert_equal [ published ], Quiz.published.to_a
  end

  test "quiz_questions are ordered by position" do
    q = quiz
    q.quiz_questions.create!(prompt: "둘째", choices: %w[a b], answer_index: 0, position: 2)
    q.quiz_questions.create!(prompt: "첫째", choices: %w[a b], answer_index: 0, position: 1)
    assert_equal %w[첫째 둘째], q.quiz_questions.reload.map(&:prompt)
  end

  test "quiz_question correct? compares selected index to answer_index" do
    question = quiz.quiz_questions.create!(prompt: "문", choices: %w[a b c], answer_index: 1, position: 1)
    assert question.correct?(1)
    assert question.correct?("1")
    assert_not question.correct?(0)
    assert_not question.correct?(nil)
  end

  test "quiz_attempt belongs to quiz and user" do
    q = quiz
    attempt = q.quiz_attempts.create!(user: @student, score: 2, answers: { "1" => 0 }, played_at: Time.current)
    assert_equal q, attempt.quiz
    assert_equal @student, attempt.user
    assert_includes @student.quiz_attempts, attempt
  end
end
