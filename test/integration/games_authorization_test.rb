require "test_helper"

# Phase 3 §3.3 — 경계 클램프(N2/#2/#3). 학생 플레이·제출 시점에 origin 별 경계를 강제한다:
#   · system: band 서버계산 일치(다른 band 행을 id 로 직접 치면 403).
#   · teacher: 학급-스코프 퀴즈는 소속 학급만(**선존 크로스-학급 published 퀴즈 id 플레이 구멍** 차단).
# 교사/총괄 manage 접근은 깨지 않는다.
class GamesAuthorizationTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "경계초")
    @room_a = Classroom.create!(school: @school, grade: 5, class_no: 1) # g56
    @room_b = Classroom.create!(school: @school, grade: 5, class_no: 2) # g56, 다른 학급
    @room_low = Classroom.create!(school: @school, grade: 1, class_no: 3) # g12
    @teacher = User.create!(school: @school, classroom: @room_a, name: "경계교사", password: "password", role: :teacher, approved: true)
    @student_a = User.create!(school: @school, classroom: @room_a, name: "A반학생", password: "password")
    @student_b = User.create!(school: @school, classroom: @room_b, name: "B반학생", password: "password")
    @student_low = User.create!(school: @school, classroom: @room_low, name: "저학년학생", password: "password")
    @book = Book.create!(title: "경계책", author: "저자", category: :recommended)
    AppSetting.set("feature_flags", { "on_demand_games" => true })
  end

  # ── 선존 구멍: 타 학급의 교사 학급-스코프 published 퀴즈를 id 로 플레이 시도 → 403 ──
  test "a student cannot play another classroom's teacher classroom-scoped quiz by id (pre-existing hole closed)" do
    quiz_a = teacher_classroom_quiz(@room_a)

    login_as @student_b
    get games_quiz_path(quiz_a)
    assert_response :forbidden, "타 학급 학급-스코프 퀴즈는 id 로도 플레이할 수 없다"

    assert_no_difference -> { QuizAttempt.count } do
      post games_attempts_path, params: { quiz_id: quiz_a.id, game: "quiz", answers: {} }
    end
    assert_response :forbidden, "제출도 경계 클램프로 차단"
  end

  test "the owning classroom's student can still play the teacher classroom-scoped quiz" do
    quiz_a = teacher_classroom_quiz(@room_a)

    login_as @student_a
    get games_quiz_path(quiz_a)
    assert_response :success, "소속 학급 학생의 정당한 플레이는 유지된다"
  end

  test "a global teacher quiz remains playable by any classroom's student" do
    global = Quiz.create!(title: "전역 퀴즈", created_by: @teacher, book: @book, scope: :global, published: true)
    global.quiz_questions.create!(prompt: "문항", choices: %w[가 나 다 라], answer_index: 0, position: 1)

    login_as @student_b
    get games_quiz_path(global)
    assert_response :success
  end

  # ── system 온디맨드: 다른 band 의 system 퀴즈를 id 로 치면 403(band 서버계산 불일치) ──
  test "a student cannot play a system quiz of a different band by id" do
    login_as @student_a
    get games_quiz_play_path(book_id: @book.id) # g56 system 퀴즈 생성
    g56_quiz = Quiz.where(origin: :system, book_id: @book.id, band: :g56).last
    delete session_path

    login_as @student_low # g12 학생
    get games_quiz_path(g56_quiz)
    assert_response :forbidden, "다른 band(g56) system 퀴즈는 g12 학생이 플레이할 수 없다"
  end

  # ── band 는 서버계산(사용자 조작 불가) — 학생은 항상 자기 band 퀴즈를 받는다 ──
  test "band is server-derived from the student's grade, not manipulable via params" do
    login_as @student_low
    get games_quiz_play_path(book_id: @book.id, band: "g56") # band 파라미터 위조 시도
    assert_response :success
    quiz = Quiz.where(origin: :system, book_id: @book.id).last
    assert_equal "g12", quiz.band, "band 는 학급 학년(g12)으로 서버계산 — params 위조가 무시된다"
  end

  # ── 존재하지 않는 book_id → 404(카탈로그 경계 밖) ──
  test "an invalid book_id yields 404 (not a silent play)" do
    login_as @student_a
    get games_quiz_play_path(book_id: 999_999)
    assert_response :not_found
  end

  # ── 교사 manage 접근은 클램프에 걸리지 않는다 ──
  test "a teacher can preview any published quiz (manage access preserved)" do
    quiz_a = teacher_classroom_quiz(@room_a)
    other_teacher = User.create!(school: @school, classroom: @room_b, name: "다른교사", password: "password", role: :teacher, approved: true)

    login_as other_teacher
    get games_quiz_path(quiz_a)
    assert_response :success, "교사는 경계 클램프 없이 미리보기 가능(manage)"
  end

  private

  def teacher_classroom_quiz(classroom)
    quiz = Quiz.create!(title: "학급 퀴즈", created_by: @teacher, book: @book, scope: :classroom,
                        classroom: classroom, published: true)
    quiz.quiz_questions.create!(prompt: "문항", choices: %w[가 나 다 라], answer_index: 0, position: 1)
    quiz
  end
end
