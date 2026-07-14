require "test_helper"

# P5.6 — 독서게임: 교사 published mcq 퀴즈(id) 플레이(quiz) → QuizAttempt + 포인트.
# 온디맨드(book_id) 진입·matching·hint_reveal 등 Phase 3 편입은 games_ondemand_test.rb 참고.
class GamesTest < ActionDispatch::IntegrationTest
  setup do
    seed_monster_species!
    seed_badges!
    @school = School.create!(name: "게임초등학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @teacher = User.create!(school: @school, classroom: @classroom, name: "게임교사", password: "password", role: :teacher)
    @student = User.create!(school: @school, classroom: @classroom, name: "게임학생", password: "password")
    @book = Book.create!(title: "게임책", author: "지은이", category: :recommended)
    @quiz = build_published_quiz
  end

  def build_published_quiz(published: true)
    quiz = Quiz.create!(title: "게임 퀴즈", created_by: @teacher, book: @book, scope: :global, published: published)
    3.times do |i|
      quiz.quiz_questions.create!(prompt: "문제#{i}", choices: %w[가 나 다 라], answer_index: 1, position: i + 1)
    end
    quiz
  end

  test "the teacher quiz show route resolves for a logged-in student" do
    login_as @student
    get games_quiz_path(@quiz)
    assert_response :success
  end

  test "quiz show renders the published quiz questions" do
    login_as @student
    get games_quiz_path(@quiz)
    assert_response :success
    assert_includes response.body, "문제0"
    assert_select "input[type=radio]"
  end

  # Phase 1 §1.2 회귀 — 플레이 뷰가 정답키를 유출하지 않는다(서버 채점·무유출).
  test "quiz play view does not leak the answer key" do
    login_as @student
    get games_quiz_path(@quiz)
    assert_response :success

    # 정답이 미리 선택(checked)되거나 정답 인덱스 키가 마크업에 노출되면 안 된다.
    assert_select "input[type=radio][checked]", false, "정답이 미리 선택되어 유출되면 안 된다"
    assert_not_includes response.body, "answer_index", "정답 인덱스 키가 뷰에 노출되면 안 된다"
  end

  test "playing the quiz records a QuizAttempt and awards points" do
    login_as @student
    all_correct = @quiz.quiz_questions.each_with_object({}) { |q, h| h[q.id.to_s] = q.answer_index }

    assert_difference -> { QuizAttempt.count }, 1 do
      assert_difference -> { @student.reload.points }, 3 * Games::QuizPlay::POINTS_PER_CORRECT do
        post games_attempts_path, params: { quiz_id: @quiz.id, game: "quiz", answers: all_correct }
      end
    end

    attempt = QuizAttempt.last
    assert_equal @student.id, attempt.user_id
    assert_equal 3, attempt.score
    assert_redirected_to games_quiz_path(@quiz)
  end

  test "partially correct answers score only the correct ones" do
    login_as @student
    questions = @quiz.quiz_questions.to_a
    answers = { questions[0].id.to_s => questions[0].answer_index, questions[1].id.to_s => 0, questions[2].id.to_s => 0 }
    # answer_index 는 1 이므로 첫 문제만 정답.

    post games_attempts_path, params: { quiz_id: @quiz.id, game: "quiz", answers: answers }
    assert_equal 1, QuizAttempt.last.score
    assert_equal Games::QuizPlay::POINTS_PER_CORRECT, @student.reload.points
  end

  test "unpublished quiz is not playable (404) and rejects attempts" do
    hidden = build_published_quiz(published: false)
    login_as @student

    get games_quiz_path(hidden)
    assert_response :not_found

    assert_no_difference -> { QuizAttempt.count } do
      post games_attempts_path, params: { quiz_id: hidden.id, game: "quiz", answers: {} }
    end
    assert_response :not_found
  end

  test "games require login" do
    get games_quiz_path(@quiz)
    assert_redirected_to new_session_path
  end
end
