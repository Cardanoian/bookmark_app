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

  # 교차-학급 IDOR 방지 — 승인 교사라도 남의 학급 id 를 주입해 퀴즈를 넣을 수 없다.
  test "a teacher cannot inject a quiz into another teacher's classroom via classroom_id" do
    other_classroom = Classroom.create!(school: @school, grade: 6, class_no: 2)
    other_teacher = User.create!(school: @school, classroom: other_classroom, name: "다른담임", role: :teacher, password: "password", approved: true)
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

  private

  def login_as(user)
    post session_path, params: {
      school_id: user.school_id, classroom_id: user.classroom_id,
      name: user.name, password: "password"
    }
  end
end
