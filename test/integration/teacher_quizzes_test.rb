require "test_helper"

# P6.2 교사 퀴즈 CRUD + 오프라인 초안 생성 + 게시(published) + 경계 인가.
class TeacherQuizzesTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "퀴즈학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @teacher = User.create!(school: @school, classroom: @classroom, name: "퀴즈담임", role: :teacher, password: "password", approved: true)
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

  private

  def login_as(user)
    post session_path, params: {
      school_id: user.school_id, classroom_id: user.classroom_id,
      name: user.name, password: "password"
    }
  end
end
