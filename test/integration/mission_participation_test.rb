require "test_helper"

# 미션 자동진행 e2e(menu_refactor 심화 PR2·PR3, §6.2 — 구 세션 join 흐름 대체).
# 발행된 미션에 자동 배정된 학생이 승인 독후감을 쓰면 EvaluateProgress→Rewarder 로 participation 이
# 완료·보상되고, ReadingStats.missions(completed_at 기준)가 1 이 되어 곰 라인(dex 13, 1→2 조건
# points:100, missions:1)의 진화 조건에 기여한다. 미션 보상 100P 가 points 조건도 함께 충족한다.
class MissionParticipationTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    seed_monster_species!
    seed_badges!
    @school = School.create!(name: "미션참여초등학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @teacher = User.create!(school: @school, classroom: @classroom, name: "미션담임",
                            email: "mp_teacher@example.com", role: :teacher, password: "password")
    @classroom.update!(teacher: @teacher)
    @student = User.create!(school: @school, classroom: @classroom, name: "미션학생", password: "password")

    # 곰 라인(dex 13) 발견 + 대표 지정. 곰 1→2 진화 조건: points:100, missions:1.
    @bear = MonsterAcquisition.new(@student).discover_monster!(13)
    @student.update!(active_monster: @bear)

    # 승인 독후감 1편 목표 + 보상 100P 미션 → 발행(학생 자동 배정).
    @mission = Mission.new(classroom: @classroom, title: "봄 독서 미션", reward_points: 100,
                           start_date: Date.current, end_date: Date.current + 7)
    @mission.mission_goals.build(goal_type: :approved_reports, target_count: 1)
    @mission.save!
    @mission.publish!
  end

  test "발행 미션의 승인 독후감이 완료·보상되고 진화 엔진으로 흐른다" do
    assert MissionParticipation.exists?(mission: @mission, user: @student), "발행 시 자동 배정돼야 한다"

    login_as @student
    post reports_path, params: { report: { book_title: "곰의 모험", body: "나는 곰과 함께 모험을 떠났다." } }
    report = @student.reports.order(:created_at).last

    # 교사 승인 → finalize_approval → EvaluateProgress → Rewarder(완료·보상).
    delete session_path
    login_as @teacher
    post approve_teacher_review_path(report)
    assert report.reload.reviewed?

    part = MissionParticipation.find_by(mission: @mission, user: @student)
    assert part.completed_at.present?, "목표 충족 시 완료돼야 한다"
    assert_equal 100, part.reward_points_awarded
    assert_equal 100, @student.reload.experience, "미션 포인트와 같은 양의 경험치가 지급돼야 한다"
    assert_operator ReadingStats.new(@student).missions, :>=, 1

    # 보상 100P(points 조건) + missions:1 → 곰 진화 가능.
    assert_includes @student.reload.evolvable_monsters, @bear.reload,
      "미션 완료(missions:1)+보상(points:100)이 곰 진화 조건에 기여해야 한다"

    login_as @student
    post evolve_monster_path(@bear.dex_no)
    assert_equal "bear_2", @bear.reload.monster_species.key
  end

  test "승인 전(미완료) 미션은 missions 지표에 잡히지 않는다" do
    login_as @student
    post reports_path, params: { report: { book_title: "그냥 책", body: "아직 승인 전." } }

    part = MissionParticipation.find_by(mission: @mission, user: @student)
    assert part.present?, "자동 배정은 됨"
    assert_nil part.completed_at, "승인 전이라 미완료"
    assert_equal 0, ReadingStats.new(@student).missions
  end

  test "특정 도서 지정 미션은 그 책 독후감 승인 때만 완료·보상된다" do
    target = Book.create!(title: "지정 도서")
    other  = Book.create!(title: "다른 도서")
    book_mission = Mission.new(classroom: @classroom, title: "지정도서 독후감", reward_points: 20,
                               start_date: Date.current, end_date: Date.current + 7)
    book_mission.mission_goals.build(goal_type: :approved_reports, target_count: 1, book: target)
    book_mission.save!
    book_mission.publish!
    part = MissionParticipation.find_by(mission: book_mission, user: @student)

    # 1) 다른 책 독후감 승인 → 지정도서 미션은 미완료.
    approve_report_for(other)
    assert_nil part.reload.completed_at, "다른 책 독후감은 지정도서 목표를 채우지 못한다"

    # 2) 지정 책 독후감 승인 → 완료·보상.
    experience_before = @student.reload.experience
    approve_report_for(target)
    assert part.reload.completed_at.present?, "지정 책 독후감으로 완료돼야 한다"
    assert_equal 20, part.reward_points_awarded
    assert_equal experience_before + 20, @student.reload.experience
  end

  private

  # 학생이 book 을 연결한 독후감을 제출하고 교사가 승인한다.
  def approve_report_for(book)
    login_as @student
    post reports_path, params: { report: { book_id: book.id, book_title: book.title, body: "#{book.title} 독후감 본문입니다." } }
    report = @student.reports.order(:created_at).last
    delete session_path
    login_as @teacher
    post approve_teacher_review_path(report)
    delete session_path
    report
  end
end
