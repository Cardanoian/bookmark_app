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
    @quiz = build_quiz("게임포인트 퀴즈")
  end

  test "owl line is not evolvable before any game is played" do
    assert_not @monster.reload.evolvable?
    assert_equal 0, ReadingStats.new(@student).quizzes
  end

  test "playing games raises points, increments quizzes, and unlocks the quizzes: evolution" do
    login_as @student

    # 서로 다른 퀴즈 4개 만점 → 포인트 100, quizzes 4 (owl_1 조건 points:100 + quizzes:3 충족).
    # 같은 퀴즈 재플레이는 파밍 방지로 적립이 0 이라, 100점은 서로 다른 퀴즈에서 모은다.
    quizzes = [ @quiz ] + Array.new(3) { |i| build_quiz("게임포인트 퀴즈 추가#{i}") }
    quizzes.each { |quiz| play_all_correct(quiz) }

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
    quizzes = [ @quiz ] + Array.new(3) { |i| build_quiz("진화 퀴즈 추가#{i}") }
    quizzes.each { |quiz| play_all_correct(quiz) }

    new_form = @student.reload.evolve_active_monster!
    assert_equal "owl_2", new_form.key, "게임 포인트로 owl_1 → owl_2 진화"
    assert_equal 0, @student.reload.points, "owl_1 진화 비용 100포인트 차감"
    assert_equal 100, @student.experience, "진화에 포인트를 써도 누적 경험치는 유지"
    assert_equal 2, @student.trainer_level, "진화에 포인트를 써도 레벨은 내려가지 않음"
    assert_equal 6, @monster.reload.dex_no, "제자리 진화(같은 라인)"
  end

  # §1.2 파밍 차단 회귀 방지 — 같은 퀴즈를 반복 제출해도 최고점 이상은 적립되지 않는다.
  test "replaying the same quiz does not farm points beyond the best score" do
    login_as @student

    play_all_correct(@quiz)
    assert_equal 25, @student.reload.points, "첫 만점은 전액 적립"
    assert_match "25포인트를 얻었어요", flash[:notice], "첫 만점은 획득 안내"

    play_all_correct(@quiz)
    assert_equal 25, @student.reload.points, "같은 퀴즈 재플레이는 추가 적립 없음(파밍 차단)"
    assert_match "추가 포인트는 없어요", flash[:notice], "재플레이 델타 0 은 정직하게 안내(획득 문구 금지)"
    refute_match "얻었어요", flash[:notice], "델타 0 일 때 '얻었어요'라고 말하지 않는다"

    play_all_correct(@quiz)
    assert_equal 3, ReadingStats.new(@student).quizzes, "플레이 횟수(quizzes) 자체는 계속 증가"
  end

  # 만점 25점(정답 5포인트 × 5문항) 게시 퀴즈 1개.
  def build_quiz(title)
    quiz = Quiz.create!(title: title, created_by: @teacher, book: @book, scope: :global, published: true)
    5.times do |i|
      quiz.quiz_questions.create!(prompt: "문제#{i}", choices: %w[정답 오답1 오답2 오답3], answer_index: 0, position: i + 1)
    end
    quiz
  end

  def play_all_correct(quiz)
    answers = quiz.quiz_questions.each_with_object({}) { |q, h| h[q.id.to_s] = q.answer_index }
    post games_attempts_path, params: { quiz_id: quiz.id, game: "quiz", answers: answers }
  end
end
