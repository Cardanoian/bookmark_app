require "test_helper"

# 챌린지 목표화 e2e(챌린지도 미션처럼 목표·진행·보상). 미션과 달리 발행·eager 배정이 없고,
# 활동 트리거(독후감 승인·게임 완료)·상세 조회 시 참여를 지연 생성해 완료·보상한다(Rewarder 멱등).
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

  # 승인 독후감 1편 목표 + 보상 N 인 학교 챌린지를 만든다.
  def school_challenge(reward: 40, book: nil)
    challenge = Challenge.new(title: "우리 학교 독서 챌린지", scope: :school, school: @school_a,
                              starts_on: Date.current, ends_on: Date.current + 14, reward_points: reward)
    goal = challenge.challenge_goals.build(goal_type: :approved_reports, target_count: 1)
    goal.challenge_goal_books.build(book: book) if book
    challenge.save!
    challenge
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

  test "학교 챌린지의 승인 독후감이 지연 참여 생성 + 완료·보상된다" do
    challenge = school_challenge(reward: 40)
    assert_not ChallengeParticipation.exists?(challenge: challenge, user: @student), "미션처럼 eager 배정하지 않는다"

    approve_report_for(@student)

    part = ChallengeParticipation.find_by(challenge: challenge, user: @student)
    assert part.present?, "활동 트리거가 참여를 지연 생성해야 한다"
    assert part.completed_at.present?, "목표 충족 시 완료돼야 한다"
    assert_equal 40, part.reward_points_awarded
    assert_equal 40, @student.reload.experience, "챌린지 보상과 같은 양의 경험치가 지급돼야 한다"
  end

  test "보상은 정확히-1회만 지급된다(재평가 멱등)" do
    challenge = school_challenge(reward: 40)
    approve_report_for(@student)
    experience_after_first = @student.reload.experience

    # 상세 조회(재평가) + 서비스 직접 재호출 — 둘 다 추가 지급 없어야 한다.
    login_as @student
    get challenge_path(challenge)
    assert_response :success
    Challenges::EvaluateProgress.new(@student).evaluate(challenge)

    assert_equal experience_after_first, @student.reload.experience, "중복 보상 금지"
    assert_equal 1, ChallengeParticipation.where(challenge: challenge, user: @student).count
  end

  test "특정 도서 지정 목표는 그 책 독후감 승인 때만 완료된다" do
    target = Book.create!(title: "지정 도서")
    other  = Book.create!(title: "다른 도서")
    challenge = school_challenge(reward: 25, book: target)

    approve_report_for(@student, book: other)
    part = ChallengeParticipation.find_by(challenge: challenge, user: @student)
    assert_nil part&.completed_at, "다른 책 독후감은 지정도서 목표를 못 채운다"

    experience_before = @student.reload.experience
    approve_report_for(@student, book: target)
    part = ChallengeParticipation.find_by(challenge: challenge, user: @student)
    assert part.completed_at.present?, "지정 책 독후감으로 완료돼야 한다"
    assert_equal experience_before + 25, @student.reload.experience
  end

  test "학교 챌린지는 다른 학교 학생에게 참여·보상되지 않는다(스코프 경계)" do
    challenge = school_challenge(reward: 40)
    approve_report_for(@student_b)

    assert_not ChallengeParticipation.exists?(challenge: challenge, user: @student_b),
      "타 학교 학생은 우리 학교 챌린지 참여 대상이 아니다"
    assert_equal 0, @student_b.reload.experience
  end

  test "전국 챌린지는 어느 학교 학생에게도 완료·보상된다" do
    challenge = Challenge.new(title: "전국 독서왕", scope: :global, starts_on: Date.current, reward_points: 30)
    challenge.challenge_goals.build(goal_type: :approved_reports, target_count: 1)
    challenge.save!

    approve_report_for(@student_b)
    part = ChallengeParticipation.find_by(challenge: challenge, user: @student_b)
    assert part&.completed_at.present?, "전국 챌린지는 타 학교 학생도 완료 대상"
    assert_equal 30, @student_b.reload.experience
  end

  test "게임 완료 목표가 game_play 트리거로 완료·보상된다" do
    challenge = Challenge.new(title: "게임 챌린지", scope: :school, school: @school_a,
                              starts_on: Date.current, reward_points: 15)
    challenge.challenge_goals.build(goal_type: :game_plays, target_count: 1)
    challenge.save!

    play = GamePlay.create!(user: @student, game_type: :quiz, played_on: Date.current)
    Challenges::EvaluateProgress.new(@student).on_game_play(play)

    part = ChallengeParticipation.find_by(challenge: challenge, user: @student)
    assert part&.completed_at.present?, "게임 완료로 목표를 채워야 한다"
    assert_equal 15, part.reward_points_awarded
    assert_equal 15, @student.reload.experience
  end

  test "학생 상세 화면에 본인 진행률과 완료 배지가 보인다" do
    challenge = school_challenge(reward: 40)
    login_as @student
    get challenge_path(challenge)
    assert_response :success
    assert_match "챌린지 목표", response.body
    assert_match "0/1", response.body            # 아직 미완료

    delete session_path
    approve_report_for(@student)
    login_as @student
    get challenge_path(challenge)
    assert_match "완료", response.body
  end

  test "목표가 없는 챌린지는 참여·보상 로직을 타지 않는다(레거시 join)" do
    challenge = Challenge.create!(title: "목표없는 챌린지", scope: :school, school: @school_a)
    approve_report_for(@student)
    assert_not ChallengeParticipation.exists?(challenge: challenge, user: @student)
  end
end
