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
    report = Report.create!(user: @student, classroom: @classroom, book_title: "책", **review_ready_attributes)
    login_as @teacher

    assert_difference -> { @student.user_monsters.count }, 1 do
      approve_as_teacher(report)
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

  # F4(BUG_FIX_PLAN §3.1): 완료 종류는 요청값(game)이 아니라 서버가 검증한 퀴즈 유형에서 정한다.
  # 재현: 객관식 퀴즈 하나에 game 값만 바꿔 보내 5종 완료 기록을 만들었다(책 소개·뒷이야기 글은 0개) —
  # distinct_games 해금 지표를 글 한 줄 안 쓰고 채울 수 있었다.
  test "객관식 퀴즈에 game 값을 바꿔 보내도 실제 퀴즈 종류(quiz)로만 기록된다 (F4)" do
    quiz = build_published_quiz
    login_as @student

    %w[book sequel classic whoami hacker].each do |forged|
      post games_attempts_path, params: { quiz_id: quiz.id, game: forged, answers: correct_answers(quiz) }
      assert_redirected_to games_quiz_path(quiz), "이동 경로도 요청값이 아니라 실제 퀴즈 종류를 따른다(game=#{forged})"
    end
    post games_attempts_path, params: { quiz_id: quiz.id, answers: correct_answers(quiz) } # game 생략

    assert_equal [ "quiz" ], @student.game_plays.reload.map(&:game_type).uniq, "완료 원장에는 quiz 만 남는다"
    assert_equal 1, @student.game_plays.count, "같은 날 같은 책 재플레이는 일일 유니크로 1행"
    assert_equal 0, BookIntro.where(user: @student).count + BookSequel.where(user: @student).count
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
    @student.game_plays.create!(game_type: :book, book: Book.create!(title: "소개책", category: :recommended), played_on: today)
    @student.game_plays.create!(game_type: :whoami, book_id: nil, played_on: today)
    login_as @student

    assert_difference -> { @student.user_monsters.where(dex_no: 6).count }, 1 do
      post games_attempts_path, params: { quiz_id: quiz.id, game: "quiz", answers: correct_answers(quiz) }
    end
    assert_includes flash[:notice], "새 몬스터"
  end

  # 조건을 충족했으나 어떤 쓰기 트리거(승인·게임·토론·스타터)도 거치지 않아 고착된 라인은,
  # 학생이 도감을 여는 순간 조회-시 self-heal 재평가로 해금된다(트리거 커버리지 갭 보정).
  # 재현: dex 10 조건 { b_or_better: 3 } 을 승인 경로가 아닌 직접 생성으로 채워 해금이 누락된 상태.
  def seed_stuck_b_or_better!
    3.times do
      Report.create!(user: @student, classroom: @classroom, book: @book, book_title: "책",
                     ai_status: :done, level: "B", reviewed: true, reviewed_at: Time.current, submitted_at: Time.current)
    end
    refute @student.user_monsters.exists?(dex_no: 10), "사전 조건: 조건 충족 전이 아니라 '충족했으나 미해금(고착)' 상태여야 한다"
  end

  test "opening the collection index heals a met-but-locked unlock (dex 10 b_or_better)" do
    seed_stuck_b_or_better!
    login_as @student

    assert_difference -> { @student.user_monsters.where(dex_no: 10).count }, 1 do
      get monsters_path
    end

    # 멱등: 재조회는 중복 해금하지 않는다(discover_monster! 의 owns_line? 가드).
    assert_no_difference -> { @student.user_monsters.where(dex_no: 10).count } do
      get monsters_path
    end
  end

  test "opening a monster detail page heals a met-but-locked unlock" do
    seed_stuck_b_or_better!
    login_as @student

    assert_difference -> { @student.user_monsters.where(dex_no: 10).count }, 1 do
      get monster_path(10)
    end
    assert_response :success
  end
end
