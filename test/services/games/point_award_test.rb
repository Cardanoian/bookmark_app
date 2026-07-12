require "test_helper"

# Phase 1 §1.3 (A1) — 멱등 델타 상한을 quiz.origin 으로 분기한다.
#   teacher : per-quiz 상한(현행 멱등). 재플레이 +0 — 엉뚱한 system 행을 읽지 않는다(C5a 회귀 가드).
#   system  : 콘텐츠축(book × band × content_axis) 상한. 재롤·표면전환 +0.
# 공통: points_awarded 저장값은 항상 this_score(델타 아님) 불변식 유지.
class Games::PointAwardTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "적립초")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @teacher = User.create!(school: @school, classroom: @classroom, name: "적립교사", password: "password", role: :teacher)
    @student = User.create!(school: @school, classroom: @classroom, name: "적립학생", password: "password")
    @book = Book.create!(title: "적립책", category: :recommended)
  end

  # ── C5a: 교사 퀴즈 재플레이 멱등 회귀 가드 ─────────────────────────────────
  test "teacher quiz replayed twice awards zero extra points (per-quiz ceiling)" do
    quiz = teacher_quiz

    first = play(quiz)
    assert_equal 25, first.points_awarded, "저장값은 this_score(만점)"
    assert_equal 25, first.awarded_delta, "첫 만점은 전액"
    assert_equal 25, @student.reload.points

    second = play(quiz)
    assert_equal 25, second.points_awarded, "재플레이도 자기 점수를 저장(델타 아님)"
    assert_equal 0, second.awarded_delta, "재플레이 추가 포인트 0"
    assert_equal 25, @student.reload.points, "교사 퀴즈 재플레이로 파밍되지 않는다"
  end

  # 회귀 방지: 교사 퀴즈 상한이 (텅 빈) system 집합을 읽으면 prior_max=0 → 매판 재지급(파밍).
  # 같은 book/band/axis 로 system 퀴즈가 존재해도 교사 퀴즈 상한은 그 행을 절대 읽지 않는다.
  test "teacher ceiling never reads system rows even when a same-axis system quiz exists" do
    t_quiz = teacher_quiz
    play(t_quiz) # 교사 퀴즈 25점 적립
    assert_equal 25, @student.reload.points

    # 같은 콘텐츠축의 system 퀴즈(0점 attempt)를 심어 둔다 — 교사 상한에 영향 주면 안 됨.
    s_quiz = system_quiz(content_version: 1)
    s_quiz.quiz_attempts.create!(user: @student, score: 0, points_awarded: 0, played_at: Time.current)

    award = Games::PointAward.new(quiz: t_quiz, user: @student)
    assert_equal 25, award.prior_max, "교사 상한은 자기 퀴즈 attempt(25)만 본다"
  end

  # ── system: 콘텐츠축 상한 — 재롤·표면전환 +0 ──────────────────────────────
  test "system re-roll (new content_version) awards zero extra on the same content axis" do
    v1 = system_quiz(content_version: 1)
    first = play(v1)
    assert_equal 25, first.awarded_delta, "첫 system 만점은 전액"
    assert_equal 25, @student.reload.points

    # 다시 뽑기 = 같은 (book, band, content_axis) 의 새 content_version system 퀴즈.
    v2 = system_quiz(content_version: 2)
    reroll = play(v2)
    assert_equal 25, reroll.points_awarded
    assert_equal 0, reroll.awarded_delta, "재롤은 콘텐츠축 상한에 걸려 +0"
    assert_equal 25, @student.reload.points
  end

  test "system surface-switch (same cached row via another surface) awards zero extra" do
    a = system_quiz(content_version: 1)
    play(a)
    assert_equal 25, @student.reload.points

    # 표면은 저장하지 않고 (book, band, content_axis) 캐시를 공유하므로, 표면 전환은 **같은**
    # system 행을 다시 플레이하는 것이다(Phase 2b 부분 유니크 인덱스가 같은 축·버전의 중복 행을
    # 금지 → 표면전환이 새 행을 만들 수 없다). 재플레이는 콘텐츠축 상한에 걸려 +0.
    switch = play(a)
    assert_equal 0, switch.awarded_delta, "표면 전환(같은 캐시 행 재플레이)도 콘텐츠축 상한에 걸려 +0"
    assert_equal 25, @student.reload.points
  end

  test "system ceiling is scoped per content axis (different axis does not block)" do
    play(system_quiz(content_version: 1, content_axis: :mcq))
    assert_equal 25, @student.reload.points

    # 다른 콘텐츠축(matching)은 별도 상한 — 추가 적립 가능.
    other = play(system_quiz(content_version: 1, content_axis: :matching))
    assert_equal 25, other.awarded_delta, "다른 축은 상한이 독립"
    assert_equal 50, @student.reload.points
  end

  private

  def teacher_quiz
    build_quiz(created_by: @teacher, origin: :teacher, content_axis: nil, band: nil, content_version: 1)
  end

  def system_quiz(content_version:, content_axis: :mcq)
    build_quiz(created_by: @teacher, origin: :system, content_axis: content_axis, band: :g56,
               content_version: content_version)
  end

  # mcq_single 5문항(만점 25점) 퀴즈. 채점은 mcq_single 로 동일(콘텐츠축만 메타로 붙는다).
  def build_quiz(created_by:, origin:, content_axis:, band:, content_version:)
    quiz = Quiz.create!(
      title: "적립 퀴즈 #{SecureRandom.hex(3)}", created_by: created_by, book: @book, scope: :global,
      published: true, origin: origin, content_axis: content_axis, band: band, content_version: content_version
    )
    5.times do |i|
      quiz.quiz_questions.create!(prompt: "문제#{i}", choices: %w[정답 오답1 오답2 오답3], answer_index: 0, position: i + 1)
    end
    quiz
  end

  def play(quiz)
    answers = quiz.quiz_questions.each_with_object({}) { |q, h| h[q.id.to_s] = q.answer_index }
    Games::QuizPlay.new(quiz: quiz, user: @student).record!(answers)
  end
end
