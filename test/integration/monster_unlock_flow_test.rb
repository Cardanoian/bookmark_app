require "test_helper"

# 몬스터 자동 해금 트리거 배선 e2e(monster_unlocks.md §4). 독후감 승인·게임 완료 같은 활동
# 확정 지점에서 조건을 충족한 라인이 지급되고 flash 로 안내되는지, 게임 원장 신뢰 경계(allowlist)를 확인한다.
class MonsterUnlockFlowTest < ActionDispatch::IntegrationTest
  setup do
    seed_monster_species!
    seed_badges!
    @school = School.create!(name: "해금플로우초")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @teacher = User.create!(school: @school, classroom: @classroom, name: "해금담임", role: :teacher, password: "password")
    @classroom.update!(teacher: @teacher)
    @student = User.create!(school: @school, classroom: @classroom, name: "해금학생", password: "password")
    @book = Book.create!(title: "해금책", author: "지은이", category: :recommended)
  end

  def build_published_quiz
    quiz = Quiz.create!(title: "해금 퀴즈", created_by: @teacher, book: @book, scope: :global, published: true)
    3.times { |i| quiz.quiz_questions.create!(prompt: "문제#{i}", choices: %w[가 나 다 라], answer_index: 1, position: i + 1) }
    quiz
  end

  def correct_answers(quiz)
    quiz.quiz_questions.each_with_object({}) { |q, h| h[q.id.to_s] = q.answer_index }
  end

  test "approving a report discovers a monster and announces it in the flash" do
    report = Report.create!(user: @student, classroom: @classroom, book_title: "책", ai_status: :done)
    login_as @teacher

    assert_difference -> { @student.user_monsters.count }, 1 do
      post approve_teacher_review_path(report)
    end
    assert @student.user_monsters.exists?(dex_no: 9), "승인 독후감 1편 → dex 09(콩닥이) 해금"
    assert_includes flash[:notice], "새 몬스터"
  end

  test "completing a quiz records a game_play ledger row with the declared surface and book" do
    quiz = build_published_quiz
    login_as @student

    assert_difference -> { GamePlay.count }, 1 do
      post games_attempts_path, params: { quiz_id: quiz.id, game: "quiz", answers: correct_answers(quiz) }
    end
    play = GamePlay.last
    assert_equal @student.id, play.user_id
    assert_equal "quiz", play.game_type
    assert_equal @book.id, play.book_id
    assert_equal Time.current.in_time_zone("Asia/Seoul").to_date, play.played_on
  end

  # 신뢰 경계: allowlist(quiz/classic/vocab/whoami/book) 밖 game 값은 원장에 기록하지 않는다(채점은 정상).
  test "a game surface outside the allowlist is not recorded in the ledger" do
    quiz = build_published_quiz
    login_as @student

    assert_no_difference -> { GamePlay.count } do
      assert_difference -> { QuizAttempt.count }, 1 do
        post games_attempts_path, params: { quiz_id: quiz.id, game: "hacker", answers: correct_answers(quiz) }
      end
    end
  end

  test "same quiz replayed the same day is deduped to one ledger row (farming block)" do
    quiz = build_published_quiz
    login_as @student

    assert_difference -> { GamePlay.count }, 1 do
      2.times { post games_attempts_path, params: { quiz_id: quiz.id, game: "quiz", answers: correct_answers(quiz) } }
    end
  end

  test "a game completion reaching a game unlock threshold discovers a monster with flash" do
    quiz = build_published_quiz
    today = Time.current.in_time_zone("Asia/Seoul").to_date
    # 앞선 2개 게임(다른 종류)을 원장에 미리 둔다. 세 번째(quiz) 완료가 game_plays:3(dex 06) 을 채운다.
    @student.game_plays.create!(game_type: :vocab, book: Book.create!(title: "어휘책", category: :recommended), played_on: today)
    @student.game_plays.create!(game_type: :whoami, book_id: nil, played_on: today)
    login_as @student

    assert_difference -> { @student.user_monsters.where(dex_no: 6).count }, 1 do
      post games_attempts_path, params: { quiz_id: quiz.id, game: "quiz", answers: correct_answers(quiz) }
    end
    assert_includes flash[:notice], "새 몬스터"
  end
end
