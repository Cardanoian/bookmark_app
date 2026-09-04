require "test_helper"

# P6.2 교사 퀴즈 CRUD + 오프라인 초안 생성 + 게시(published) + 경계 인가.
class TeacherQuizzesTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "퀴즈학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @teacher = User.create!(school: @school, classroom: @classroom, name: "퀴즈담임", role: :teacher, password: "password")
    @classroom.update!(teacher: @teacher)
    @student = User.create!(school: @school, classroom: @classroom, name: "퀴즈학생", password: "password")
    @book = Book.create!(title: "마당을 나온 암탉", author: "황선미", summary: "잎싹 이야기", category: :recommended)
  end

  test "create with a book generates offline draft questions" do
    login_as @teacher
    assert_difference -> { Quiz.count }, 1 do
      post teacher_quizzes_path, params: { quiz: { title: "암탉 퀴즈", book_id: @book.id } }
    end

    quiz = Quiz.order(:created_at).last
    assert_equal @teacher.id, quiz.created_by_id
    assert_equal @classroom.id, quiz.classroom_id
    assert_operator quiz.quiz_questions.count, :>=, 1, "오프라인 초안 문항이 생성돼야 한다"
  end

  test "update publishes the quiz" do
    quiz = Quiz.create!(title: "게시전", created_by: @teacher, classroom: @classroom, scope: :classroom)
    login_as @teacher
    patch teacher_quiz_path(quiz), params: { quiz: { published: "1" } }
    assert quiz.reload.published?
  end

  # 폼은 1-based(answer_number)로 받되 저장은 0-based(answer_index) 불변 — 채점까지 정합 확인.
  test "update saves answer_number as 1-based while answer_index stays 0-based for grading" do
    quiz = Quiz.create!(title: "정답변환", created_by: @teacher, classroom: @classroom, scope: :classroom)
    question = quiz.quiz_questions.create!(prompt: "문", choices: %w[a b c d], answer_index: 3, position: 1)

    login_as @teacher
    patch teacher_quiz_path(quiz), params: {
      quiz: { quiz_questions_attributes: { "0" => { id: question.id, answer_number: 1 } } }
    }

    question.reload
    assert_equal 0, question.answer_index
    assert question.correct?(0)
  end

  # 체크박스 2개 → mcq_multi 로 승격되고, 학생 플레이 화면이 체크박스를 그리며, 배열 제출이
  # 그대로 채점된다(서버는 무변경 — submitted_answers 의 to_unsafe_h 가 배열을 보존한다).
  test "update promotes a question to mcq_multi when two answers are checked" do
    quiz = Quiz.create!(title: "복수정답", created_by: @teacher, classroom: @classroom, scope: :classroom)
    question = quiz.quiz_questions.create!(prompt: "문", choices: %w[가 나 다 라], answer_index: 0, position: 1)

    login_as @teacher
    patch teacher_quiz_path(quiz), params: {
      quiz: { quiz_questions_attributes: { "0" => { id: question.id, answer_indexes: [ "", "0", "2" ] } } }
    }

    question.reload
    assert question.mcq_multi?
    assert_equal [ 0, 2 ], question.answer
    assert_nil question.answer_index
  end

  test "update rejects duplicate choices instead of saving them" do
    quiz = Quiz.create!(title: "중복보기", created_by: @teacher, classroom: @classroom, scope: :classroom)
    question = quiz.quiz_questions.create!(prompt: "문", choices: %w[가 나 다 라], answer_index: 0, position: 1)

    login_as @teacher
    patch teacher_quiz_path(quiz), params: {
      quiz: { quiz_questions_attributes: { "0" => { id: question.id, choices: [ "가", "가", "다", "라" ] } } }
    }

    assert_response :unprocessable_entity
    assert_equal %w[가 나 다 라], question.reload.choices
  end

  # 이 화면은 문항 타입을 가리지 않는다. 체크박스를 무조건 그리면 hint_reveal 문항은 보기가 없어
  # 체크가 0개가 되고 setter 가 타입을 덮어 **저장 자체가 불가능**해진다.
  test "editing a quiz that contains a hint_reveal question does not corrupt it" do
    quiz = Quiz.create!(title: "혼합", created_by: @teacher, classroom: @classroom, scope: :classroom)
    hint = quiz.quiz_questions.create!(prompt: "누구게?", question_type: :hint_reveal,
                                       answer: "홍길동", content: { hints: %w[힌트1 힌트2] }, position: 1)

    login_as @teacher
    get edit_teacher_quiz_path(quiz)
    assert_response :success
    assert_select "input[name=?]", "quiz[quiz_questions_attributes][0][answer_indexes][]", count: 0

    patch teacher_quiz_path(quiz), params: {
      quiz: { published: "1", quiz_questions_attributes: { "0" => { id: hint.id, prompt: "고친 질문" } } }
    }

    hint.reload
    assert hint.hint_reveal?
    assert_equal "홍길동", hint.answer
    assert quiz.reload.published?
  end

  test "index lists the teacher's quizzes" do
    Quiz.create!(title: "목록퀴즈", created_by: @teacher, classroom: @classroom, scope: :classroom)
    login_as @teacher
    get teacher_quizzes_path
    assert_response :success
    assert_match "목록퀴즈", response.body
  end

  test "destroy removes the quiz" do
    quiz = Quiz.create!(title: "삭제퀴즈", created_by: @teacher, classroom: @classroom, scope: :classroom)
    login_as @teacher
    assert_difference -> { Quiz.count }, -1 do
      delete teacher_quiz_path(quiz)
    end
  end

  test "a student is forbidden from quiz management" do
    login_as @student
    get teacher_quizzes_path
    assert_response :forbidden
  end

  # 교차-학급 IDOR 방지 — 승인 교사라도 남의 학급 id 를 주입해 퀴즈를 넣을 수 없다.
  test "a teacher cannot inject a quiz into another teacher's classroom via classroom_id" do
    other_classroom = Classroom.create!(school: @school, grade: 6, class_no: 2)
    other_teacher = User.create!(school: @school, classroom: other_classroom, name: "다른담임", role: :teacher, password: "password")
    other_classroom.update!(teacher: other_teacher)

    login_as @teacher
    assert_no_difference -> { Quiz.where(classroom_id: other_classroom.id).count } do
      post teacher_quizzes_path, params: { quiz: { title: "침입퀴즈", classroom_id: other_classroom.id } }
    end
    assert_response :forbidden
  end

  # 교차-학급 IDOR 방지 — 수정으로 소유 퀴즈를 남의 학급으로 재배정할 수 없다.
  test "a teacher cannot reassign a quiz to another classroom via update" do
    other_classroom = Classroom.create!(school: @school, grade: 6, class_no: 3)
    quiz = Quiz.create!(title: "내퀴즈", created_by: @teacher, classroom: @classroom, scope: :classroom)

    login_as @teacher
    patch teacher_quiz_path(quiz), params: { quiz: { title: "수정", classroom_id: other_classroom.id } }
    assert_equal @classroom.id, quiz.reload.classroom_id, "classroom_id 는 수정으로 바뀌지 않는다"
  end

  # WS-B 서버 검증 — 폼리스 도서 검색이 넘긴 book_id 를 신뢰하지 않는다.
  # 카탈로그 도서(비-searched)만 연결하고, searched 캐시·무효 id 는 미연결(nil)이다.
  test "create links a valid catalog book" do
    login_as @teacher
    post teacher_quizzes_path, params: { quiz: { title: "연결", book_id: @book.id } }
    assert_equal @book.id, Quiz.order(:created_at).last.book_id
  end

  test "create does not link a searched-cache book" do
    searched = Book.create!(title: "검색캐시", category: :searched)
    login_as @teacher
    post teacher_quizzes_path, params: { quiz: { title: "검색연결", book_id: searched.id } }
    assert_nil Quiz.order(:created_at).last.book_id, "searched 캐시 도서는 퀴즈에 연결되지 않는다"
  end

  test "create does not link a nonexistent book" do
    login_as @teacher
    post teacher_quizzes_path, params: { quiz: { title: "유령도서", book_id: 999_999 } }
    assert_nil Quiz.order(:created_at).last.book_id
  end

  test "update links a valid catalog book and rejects a searched one" do
    quiz = Quiz.create!(title: "수정도서", created_by: @teacher, classroom: @classroom, scope: :classroom)
    searched = Book.create!(title: "검색캐시2", category: :searched)
    login_as @teacher

    patch teacher_quiz_path(quiz), params: { quiz: { book_id: @book.id } }
    assert_equal @book.id, quiz.reload.book_id

    patch teacher_quiz_path(quiz), params: { quiz: { book_id: searched.id } }
    assert_nil quiz.reload.book_id, "searched 캐시로 재지정하면 연결되지 않는다"
  end

  private
end
