require "test_helper"

# 챌린지 목표화 e2e(챌린지도 미션처럼 목표·진행·보상). 미션과 달리 발행·eager 배정이 없고,
# 학생이 '참여하기'를 누른 시점(joined_at)에 참여 원장이 생기며 **그 이후 활동만** 집계·보상한다.
# 참여 대상은 스코프로 결정된다: 전국(global)=모든 학생, 우리 학교(school)=그 학교 학생만.
class ChallengeGoalsTest < ActionDispatch::IntegrationTest
  setup do
    seed_monster_species!
    seed_badges!
    @school_a = School.create!(name: "챌린지목표A초")
    @school_b = School.create!(name: "챌린지목표B초")
    @room_a = Classroom.create!(school: @school_a, grade: 5, class_no: 1)
    @room_b = Classroom.create!(school: @school_b, grade: 5, class_no: 1)
    @teacher = User.create!(school: @school_a, classroom: @room_a, name: "목표담임",
                            email: "cg_teacher@example.com", role: :teacher, password: "password")
    @room_a.update!(teacher: @teacher)
    @teacher_b = User.create!(school: @school_b, classroom: @room_b, name: "타교담임",
                              email: "cg_teacher_b@example.com", role: :teacher, password: "password")
    @room_b.update!(teacher: @teacher_b)
    @student = User.create!(school: @school_a, classroom: @room_a, name: "목표학생", password: "password")
    @student_b = User.create!(school: @school_b, classroom: @room_b, name: "타교학생", password: "password")
  end

  # 승인 독후감 1편 목표 + 보상 N 인 학교 챌린지를 만든다. starts_on 은 과거라 참여 전 활동도
  # '챌린지 기간 안'이지만 참여 이후가 아니므로 집계되지 않아야 한다.
  def school_challenge(reward: 40, book: nil)
    challenge = Challenge.new(title: "우리 학교 독서 챌린지", scope: :school, school: @school_a,
                              starts_on: Date.current - 7, ends_on: Date.current + 14, reward_points: reward)
    goal = challenge.challenge_goals.build(goal_type: :approved_reports, target_count: 1)
    goal.challenge_goal_books.build(book: book) if book
    challenge.save!
    challenge
  end

  # 학생이 '참여하기'를 눌러 참여한다(참여 원장 생성 = 집계 시작점).
  def join_challenge(student, challenge)
    login_as student
    post join_challenge_path(challenge)
    delete session_path
    ChallengeParticipation.find_by(challenge: challenge, user: student)
  end

  # 학생이 book(선택)을 연결한 독후감을 제출하고 그 학급 담임이 승인한다(finalize_approval 트리거).
  def approve_report_for(student, book: nil, title: "챌린지 도서")
    login_as student
    params = { report: { book_title: (book&.title || title), body: "#{title} 독후감 본문입니다." } }
    params[:report][:book_id] = book.id if book
    post reports_path, params: params
    report = student.reports.order(:created_at).last
    delete session_path
    login_as student.classroom.teacher
    post approve_teacher_review_path(report)
    delete session_path
    report
  end

  test "참여한 학생의 승인 독후감이 완료·보상된다" do
    challenge = school_challenge(reward: 40)
    assert_not ChallengeParticipation.exists?(challenge: challenge, user: @student), "미션처럼 eager 배정하지 않는다"

    part = join_challenge(@student, challenge)
    assert part.present?, "참여하기가 참여 원장을 만들어야 한다"
    assert part.joined_at.present?, "참여 시각이 집계 시작점이다"

    approve_report_for(@student)

    part.reload
    assert part.completed_at.present?, "참여 후 승인 독후감으로 완료돼야 한다"
    assert_equal 40, part.reward_points_awarded
    assert_equal 40, @student.reload.experience, "챌린지 보상과 같은 양의 경험치가 지급돼야 한다"
  end

  test "참여 전에 쓴 독후감은 집계되지 않는다" do
    challenge = school_challenge(reward: 40)

    # 챌린지 기간(7일 전 시작) 안이지만 참여 이전인 독후감.
    early = approve_report_for(@student, title: "참여 전 책")
    early.update_columns(created_at: 3.days.ago)
    experience_before = @student.reload.experience

    part = join_challenge(@student, challenge)
    assert_nil part.completed_at, "참여 전 활동으로는 완료되지 않는다"
    assert_equal experience_before, @student.reload.experience, "참여 전 활동에 보상이 지급되면 안 된다"

    login_as @student
    get challenges_path
    assert_response :success
    assert_match "0/1", response.body, "목록 진행률은 참여 이후 활동만 센다"

    # 참여 이후 독후감은 정상 집계된다.
    delete session_path
    approve_report_for(@student, title: "참여 후 책")
    assert part.reload.completed_at.present?
    assert_equal experience_before + 40, @student.reload.experience
  end

  test "참여 전에 플레이한 게임은 집계되지 않는다" do
    challenge = Challenge.new(title: "게임 챌린지", scope: :school, school: @school_a,
                              starts_on: Date.current - 7, reward_points: 15)
    challenge.challenge_goals.build(goal_type: :game_plays, target_count: 1)
    challenge.save!

    early = GamePlay.create!(user: @student, game_type: :quiz, played_on: Date.current - 3)
    Challenges::EvaluateProgress.new(@student).on_game_play(early)
    assert_not ChallengeParticipation.exists?(challenge: challenge, user: @student), "미참여 학생은 평가 대상이 아니다"

    part = join_challenge(@student, challenge)
    assert_nil part.completed_at, "참여 전 게임으로는 완료되지 않는다"
    assert_equal 0, @student.reload.experience

    play = GamePlay.create!(user: @student, game_type: :whoami, played_on: Date.current)
    Challenges::EvaluateProgress.new(@student).on_game_play(play)
    assert part.reload.completed_at.present?, "참여 후 게임 완료로 목표를 채워야 한다"
    assert_equal 15, part.reward_points_awarded
    assert_equal 15, @student.reload.experience
  end

  test "참여하지 않은 학생은 진행·보상 대상이 아니다" do
    challenge = school_challenge(reward: 40)

    approve_report_for(@student)

    assert_not ChallengeParticipation.exists?(challenge: challenge, user: @student),
      "참여하기를 누르지 않으면 참여 원장이 생기지 않는다"
    assert_equal 0, @student.reload.experience

    login_as @student
    get challenges_path
    assert_response :success
    assert_select ".progress-bar", { count: 0 }, "미참여 카드에는 진행률 막대가 없다"
  end

  test "보상은 정확히-1회만 지급된다(재평가 멱등)" do
    challenge = school_challenge(reward: 40)
    join_challenge(@student, challenge)
    approve_report_for(@student)
    experience_after_first = @student.reload.experience

    # 상세 조회(재평가) + 서비스 직접 재호출 + 재참여 — 모두 추가 지급이 없어야 한다.
    login_as @student
    get challenge_path(challenge)
    assert_response :success
    post join_challenge_path(challenge)
    Challenges::EvaluateProgress.new(@student).evaluate(challenge)

    assert_equal experience_after_first, @student.reload.experience, "중복 보상 금지"
    assert_equal 1, ChallengeParticipation.where(challenge: challenge, user: @student).count
  end

  test "재참여해도 참여 시각(집계 시작점)은 앞으로 밀리지 않는다" do
    challenge = school_challenge(reward: 40)
    part = join_challenge(@student, challenge)
    original_joined_at = part.joined_at

    login_as @student
    post join_challenge_path(challenge)

    assert_equal original_joined_at.to_i, part.reload.joined_at.to_i
  end

  test "특정 도서 지정 목표는 그 책 독후감 승인 때만 완료된다" do
    target = Book.create!(title: "지정 도서")
    other  = Book.create!(title: "다른 도서")
    challenge = school_challenge(reward: 25, book: target)
    part = join_challenge(@student, challenge)

    approve_report_for(@student, book: other)
    assert_nil part.reload.completed_at, "다른 책 독후감은 지정도서 목표를 못 채운다"

    experience_before = @student.reload.experience
    approve_report_for(@student, book: target)
    assert part.reload.completed_at.present?, "지정 책 독후감으로 완료돼야 한다"
    assert_equal experience_before + 25, @student.reload.experience
  end

  test "학교 챌린지는 다른 학교 학생에게 참여·보상되지 않는다(스코프 경계)" do
    challenge = school_challenge(reward: 40)

    login_as @student_b
    post join_challenge_path(challenge)
    assert_response :forbidden, "타 학교 학생은 참여할 수 없다"
    delete session_path

    approve_report_for(@student_b)

    assert_not ChallengeParticipation.exists?(challenge: challenge, user: @student_b),
      "타 학교 학생은 우리 학교 챌린지 참여 대상이 아니다"
    assert_equal 0, @student_b.reload.experience
  end

  test "전국 챌린지는 어느 학교 학생에게도 완료·보상된다" do
    challenge = Challenge.new(title: "전국 독서왕", scope: :global, starts_on: Date.current, reward_points: 30)
    challenge.challenge_goals.build(goal_type: :approved_reports, target_count: 1)
    challenge.save!

    part = join_challenge(@student_b, challenge)
    approve_report_for(@student_b)
    assert part.reload.completed_at.present?, "전국 챌린지는 타 학교 학생도 완료 대상"
    assert_equal 30, @student_b.reload.experience
  end

  test "학생 상세 화면에 본인 진행률과 완료 배지가 보인다" do
    challenge = school_challenge(reward: 40)
    login_as @student
    get challenge_path(challenge)
    assert_response :success
    assert_match "챌린지 목표", response.body
    assert_match "참여한 뒤에 쓴 독후감·게임만", response.body   # 미참여 안내

    delete session_path
    join_challenge(@student, challenge)
    login_as @student
    get challenge_path(challenge)
    assert_match "0/1", response.body                          # 참여 직후 진행률

    delete session_path
    approve_report_for(@student)
    login_as @student
    get challenge_path(challenge)
    assert_match "완료", response.body
  end

  test "목표가 없는 챌린지는 보상 로직을 타지 않는다(레거시 join)" do
    challenge = Challenge.create!(title: "목표없는 챌린지", scope: :school, school: @school_a)
    part = join_challenge(@student, challenge)
    approve_report_for(@student)

    assert_nil part.reload.completed_at
    assert_equal 0, part.reward_points_awarded
    assert_equal 0, @student.reload.experience
  end
end
