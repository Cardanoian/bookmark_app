require "test_helper"

# 미션 진행도 계산(menu_refactor 심화 §2.A.2·§6.1) — 목표 인정 규칙·기간 경계·전학 clamp·AND·batch.
class Missions::ProgressCalculatorTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "진행초")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @student = User.create!(school: @school, classroom: @classroom, name: "진행생", password: "password")
    @mission = build_mission(goals: [ { goal_type: :approved_reports, target_count: 2 } ])
    @participation = MissionParticipation.create!(mission: @mission, user: @student, assigned_at: @mission.start_date.to_time)
  end

  def build_mission(goals:, start_date: Date.current - 2, end_date: Date.current + 2)
    mission = Mission.new(classroom: @classroom, title: "미션", start_date: start_date, end_date: end_date)
    goals.each { |g| mission.mission_goals.build(g) }
    mission.status = :published
    mission.save!
    mission
  end

  def report(created_at:, reviewed: true, revision_of: nil, classroom: @classroom)
    Report.create!(user: @student, classroom: classroom, book_title: "책",
                   reviewed: reviewed, revision_of: revision_of, created_at: created_at)
  end

  def calc(participation = @participation)
    Missions::ProgressCalculator.new(participation.mission, participation.user, participation: participation)
  end

  test "승인·원본·기간내 독후감만 approved_reports 로 센다" do
    report(created_at: Time.current)                            # 인정
    report(created_at: Time.current, reviewed: false)           # 미승인 제외
    original = report(created_at: Time.current)
    report(created_at: Time.current, revision_of: original)     # 고쳐쓰기 제외
    result = calc.call
    row = result[:goals].first
    assert_equal 2, row[:current]      # 승인 원본 2편(original 포함)
    assert row[:met]
    assert result[:completed]
  end

  test "기간 밖(시작 전·종료 후 제출) 독후감은 제외" do
    zone = Missions::ProgressCalculator::ZONE
    before = zone.local(@mission.start_date.year, @mission.start_date.month, @mission.start_date.day) - 1.second
    after  = zone.local(@mission.end_date.year, @mission.end_date.month, @mission.end_date.day) + 1.day
    report(created_at: before)
    report(created_at: after)
    assert_equal 0, calc.call[:goals].first[:current]
  end

  test "기간 경계일(시작일 자정·종료일 종료직전)은 포함" do
    zone = Missions::ProgressCalculator::ZONE
    start_midnight = zone.local(@mission.start_date.year, @mission.start_date.month, @mission.start_date.day)
    end_last = zone.local(@mission.end_date.year, @mission.end_date.month, @mission.end_date.day) + 1.day - 1.second
    report(created_at: start_midnight)
    report(created_at: end_last)
    assert_equal 2, calc.call[:goals].first[:current]
  end

  test "타 학급 스탬프 독후감은 approved_reports 에서 제외" do
    other = Classroom.create!(school: @school, grade: 5, class_no: 2)
    report(created_at: Time.current, classroom: other)
    report(created_at: Time.current)                            # 우리 학급 1편
    assert_equal 1, calc.call[:goals].first[:current]
  end

  test "game_plays 목표는 participation 배정기간으로 clamp(전학 경계)" do
    mission = build_mission(goals: [ { goal_type: :game_plays, target_count: 2 } ])
    part = MissionParticipation.create!(mission: mission, user: @student,
                                        assigned_at: mission.start_date.to_time,
                                        unassigned_at: (Date.current - 1).to_time)  # 어제 이탈
    book = Book.create!(title: "게임책")
    GamePlay.create!(user: @student, game_type: :quiz, book: book, played_on: Date.current - 1)  # 이탈 전(인정)
    GamePlay.create!(user: @student, game_type: :classic, book: book, played_on: Date.current)   # 이탈 후(제외)
    assert_equal 1, calc(part).call[:goals].first[:current]
  end

  test "여러 목표는 모두 충족(AND)해야 완료" do
    mission = build_mission(goals: [
      { goal_type: :approved_reports, target_count: 1 },
      { goal_type: :game_plays, target_count: 1 }
    ])
    part = MissionParticipation.create!(mission: mission, user: @student, assigned_at: mission.start_date.to_time)
    report(created_at: Time.current)
    assert_not calc(part).completed?    # 독후감만 충족, 게임 미충족
    GamePlay.create!(user: @student, game_type: :quiz, book: Book.create!(title: "책2"), played_on: Date.current)
    assert calc(part).completed?
  end

  test "목표가 없으면 completed? 는 false(vacuous-true 방지)" do
    mission = Mission.new(classroom: @classroom, title: "무목표", start_date: Date.current, end_date: Date.current + 1)
    mission.save!(validate: false)  # 발행 검증 우회(목표 0)
    part = MissionParticipation.create!(mission: mission, user: @student)
    assert_not Missions::ProgressCalculator.new(mission, @student, participation: part).completed?
  end

  test "batch 는 단건과 동일한 met 판정을 낸다(N+1 제거)" do
    report(created_at: Time.current)
    report(created_at: Time.current)
    batch = Missions::ProgressCalculator.batch(@mission, participations: [ @participation ])
    single = calc.call
    assert_equal single[:completed], batch[@student.id][:completed]
    assert_equal single[:goals].first[:current], batch[@student.id][:goals].first[:current]
  end
end
