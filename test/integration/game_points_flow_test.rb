require "test_helper"

# P5.6 게이트 — 독서게임 플레이가 Phase 4 게임화로 흐르는지 증명:
# 게임 → 포인트 상승 → ReadingStats.quizzes 증가 → quizzes: 조건 진화(owl 라인) → 레벨업.
class GamePointsFlowTest < ActionDispatch::IntegrationTest
  setup do
    seed_monster_species!
    seed_badges!
    @school = School.create!(name: "게임포인트초")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @teacher = User.create!(school: @school, classroom: @classroom, name: "게임포인트교사", password: "password", role: :teacher)
    @student = User.create!(school: @school, classroom: @classroom, name: "게임포인트학생", password: "password")
    @book = Book.create!(title: "게임포인트책", author: "지은이", category: :recommended)

    # 지식 속성 owl 라인(dex 6): owl_1 진화 조건 = { points: 100, quizzes: 3 }.
    @monster = MonsterAcquisition.new(@student).discover_monster!("owl_1")
    @student.update!(active_monster: @monster)

    # 5문항 게시 퀴즈(문항당 정답 5포인트 → 만점 25점/판).
    @quiz = Quiz.create!(title: "게임포인트 퀴즈", created_by: @teacher, book: @book, scope: :global, published: true)
    5.times do |i|
      @quiz.quiz_questions.create!(prompt: "문제#{i}", choices: %w[정답 오답1 오답2 오답3], answer_index: 0, position: i + 1)
    end
  end

  test "owl line is not evolvable before any game is played" do
    assert_not @monster.reload.evolvable?
    assert_equal 0, ReadingStats.new(@student).quizzes
  end

  test "playing games raises points, increments quizzes, and unlocks the quizzes: evolution" do
    login_as @student
    all_correct = @quiz.quiz_questions.each_with_object({}) { |q, h| h[q.id.to_s] = q.answer_index }

    # 4판 만점 → 포인트 100, quizzes 4 (owl_1 조건 points:100 + quizzes:3 충족).
    4.times do
      post games_attempts_path, params: { quiz_id: @quiz.id, game: "quiz", answers: all_correct }
    end

    @student.reload
    assert_equal 100, @student.points, "게임 포인트가 누적된다"
    assert_equal 4, ReadingStats.new(@student).quizzes, "quiz_attempts 가 quizzes 로 집계된다"

    # 진화 조건(quizzes:) 충족 → Phase 4 게임화 반영.
    assert @monster.reload.evolvable?, "owl_1 이 진화 가능해진다"
    assert @student.check_evolution!, "활성 몬스터 진화 신호가 켜진다"

    # 레벨업(100 포인트 → 트레이너 레벨 2)도 게임 포인트로 발생.
    assert_equal 2, @student.trainer_level
  end

  test "the awarded game points actually advance the evolution in place" do
    login_as @student
    all_correct = @quiz.quiz_questions.each_with_object({}) { |q, h| h[q.id.to_s] = q.answer_index }
    4.times do
      post games_attempts_path, params: { quiz_id: @quiz.id, game: "quiz", answers: all_correct }
    end

    new_form = @student.reload.evolve_active_monster!
    assert_equal "owl_2", new_form.key, "게임 포인트로 owl_1 → owl_2 진화"
    assert_equal 6, @monster.reload.dex_no, "제자리 진화(같은 라인)"
  end

  def login_as(user)
    post session_path, params: {
      school_id: user.school_id, classroom_id: user.classroom_id,
      name: user.name, password: "password"
    }
  end
end
