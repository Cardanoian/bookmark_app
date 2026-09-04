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

  # 폼 입력(1-based) ↔ 저장(0-based, answer_index) 왕복. 저장·채점 계약은 answer_index 로 불변.
  test "answer_number is a 1-based virtual accessor over answer_index" do
    question = quiz.quiz_questions.create!(prompt: "문", choices: %w[a b c], answer_index: 0, position: 1)
    assert_equal 1, question.answer_number

    question.answer_number = 3
    assert_equal 2, question.answer_index
    assert_equal 3, question.answer_number

    question.answer_number = nil
    assert_nil question.answer_index

    question.answer_number = ""
    assert_nil question.answer_index
  end

  test "answer_number getter returns nil when answer_index is nil" do
    question = quiz.quiz_questions.build(prompt: "문", choices: %w[a b], position: 1)
    assert_nil question.answer_number
  end

  # ── 복수 정답(answer_indexes) ──────────────────────────────────────────────
  test "answer_indexes= keeps a single pick on mcq_single and promotes two picks to mcq_multi" do
    question = quiz.quiz_questions.build(prompt: "문", choices: %w[가 나 다 라], position: 1)

    question.answer_indexes = [ "2" ]
    assert question.mcq_single?
    assert_equal 2, question.answer_index
    assert_equal [ 2 ], question.answer_indexes

    question.answer_indexes = [ "0", "2" ]
    assert question.mcq_multi?
    assert_nil question.answer_index
    assert_equal [ 0, 2 ], question.answer
    assert question.valid?, question.errors.full_messages.to_sentence
  end

  test "answer_indexes= ignores the blank sentinel the form sends when nothing is checked" do
    question = quiz.quiz_questions.build(prompt: "문", choices: %w[가 나 다 라], position: 1)
    question.answer_indexes = [ "", "1" ]

    assert question.mcq_single?
    assert_equal 1, question.answer_index
  end

  # 총괄 화면은 문항 타입을 가리지 않고 전 퀴즈를 편집한다. 가드가 없으면 hint_reveal 문항에
  # 체크 0개가 들어와 question_type 을 mcq 로 덮고 정답 문자열을 날려 **저장 자체가 불가능**해진다.
  test "answer_indexes= is a no-op on non-mcq questions so their answers survive" do
    hint = quiz.quiz_questions.build(prompt: "누구게?", question_type: :hint_reveal,
                                     answer: "홍길동", content: { hints: %w[힌트1 힌트2] }, position: 1)

    hint.answer_indexes = [ "" ]
    assert hint.hint_reveal?, "타입이 mcq 로 덮이면 안 된다"
    assert_equal "홍길동", hint.answer
    assert hint.valid?, hint.errors.full_messages.to_sentence

    hint.answer_indexes = [ "0", "1" ]
    assert hint.hint_reveal?
    assert_equal "홍길동", hint.answer
  end

  # ── 보기 중복 차단 ─────────────────────────────────────────────────────────
  test "choices must be distinct (앞뒤 공백만 다른 것도 같은 보기로 본다)" do
    question = quiz.quiz_questions.build(prompt: "문", choices: [ "가", "나", " 가 ", "라" ],
                                         answer_index: 0, position: 1)

    assert_not question.valid?
    assert_match(/서로 달라야/, question.errors.full_messages.to_sentence)
  end

  # AI·시드 유래 레거시 행에 중복이 있어도 질문만 고치는 저장은 막히면 안 된다.
  test "a legacy row with duplicate choices can still be edited when choices are untouched" do
    question = quiz.quiz_questions.create!(prompt: "문", choices: %w[가 나 다 라], answer_index: 0, position: 1)
    question.update_column(:choices, %w[가 가 다 라])
    question.reload

    question.prompt = "고친 질문"
    assert question.valid?, "choices 를 건드리지 않은 저장은 통과해야 한다: #{question.errors.full_messages}"
  end

  test "answer index must fall inside the choice list" do
    question = quiz.quiz_questions.build(prompt: "문", choices: %w[가 나], position: 1)
    question.answer_indexes = [ "5" ]

    assert_not question.valid?
    assert_match(/보기 범위/, question.errors.full_messages.to_sentence)
  end

  test "quiz_attempt belongs to quiz and user" do
    q = quiz
    attempt = q.quiz_attempts.create!(user: @student, score: 2, answers: { "1" => 0 }, played_at: Time.current)
    assert_equal q, attempt.quiz
    assert_equal @student, attempt.user
    assert_includes @student.quiz_attempts, attempt
  end
end
