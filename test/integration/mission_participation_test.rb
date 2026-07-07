require "test_helper"

# P4.11 게이트 — 미션 참여가 진화 엔진으로 흘러 들어감을 증명.
# 학생이 미션에 참여하고 그 아래 승인 독후감을 쓰면 ReadingStats.missions >= 1 이 되고,
# 이것이 곰 라인(dex 13, 1→2 조건 points:100, missions:1)의 진화 조건에 기여한다.
class MissionParticipationTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    seed_monster_species!
    seed_badges!
    @school = School.create!(name: "미션참여초등학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @teacher = User.create!(school: @school, classroom: @classroom, name: "미션담임", role: :teacher, password: "password", approved: true)
    @classroom.update!(teacher: @teacher)
    @student = User.create!(school: @school, classroom: @classroom, name: "미션학생", password: "password")

    # 곰 라인(dex 13) 발견 + 대표 지정. 곰 1→2 진화 조건: points:100, missions:1.
    @bear = MonsterAcquisition.new(@student).discover_monster!(13)
    @student.update!(active_monster: @bear)
    @mission = Mission.create!(classroom: @classroom, title: "봄 독서 미션")
  end

  test "mission participation links the report and drives the evolution engine" do
    login_as @student

    # 1) 미션 참여 → 다음 작성 글 연결 플래그
    post join_mission_path(@mission)
    assert_redirected_to new_report_path

    # 2) 미션 아래에서 독후감 작성 → mission_id 연결
    post reports_path, params: { report: { book_title: "곰의 모험", body: "나는 곰과 함께 모험을 떠났다." } }
    report = @student.reports.order(:created_at).last
    assert_equal @mission.id, report.mission_id, "작성한 독후감이 미션에 연결되어야 한다"

    # 3) 교사 승인
    delete session_path
    login_as @teacher
    post approve_teacher_review_path(report)
    assert report.reload.reviewed?

    # 4) 미션 참여가 ReadingStats.missions 에 집계됨
    assert_operator ReadingStats.new(@student).missions, :>=, 1

    # 5) 포인트 100 충족 → 곰 라인이 진화 가능(missions:1 조건 기여)
    @student.award_points(100)
    assert_includes @student.evolvable_monsters, @bear.reload,
      "미션 참여(missions:1)가 곰 라인 진화 조건에 기여해야 한다"

    # 6) 실제 진화까지 이어짐
    login_as @student
    post evolve_monster_path(@bear.dex_no)
    assert_equal "bear_2", @bear.reload.monster_species.key
  end

  test "a report written without joining a mission is not linked" do
    login_as @student

    post reports_path, params: { report: { book_title: "그냥 책", body: "미션 없이 쓴 글." } }

    report = @student.reports.order(:created_at).last
    assert_nil report.mission_id
    assert_equal 0, ReadingStats.new(@student).missions
  end

  private

  def login_as(user)
    post session_path, params: {
      school_id: user.school_id, classroom_id: user.classroom_id,
      name: user.name, password: "password"
    }
  end
end
