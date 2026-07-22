require "test_helper"

# 미션 정책 학급 경계(challenge-mission-detail-pages Step 3). 학생용 미션 상세를 최상위 노출하므로
# show? 를 학급 경계로 강화했다: 타 학급/미발행 미션은 학생에게 차단, 담임·총괄은 허용.
class MissionPolicyTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "미션정책초")
    @class1 = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @class2 = Classroom.create!(school: @school, grade: 5, class_no: 2)

    @teacher = User.create!(school: @school, name: "미션담임", role: :teacher, email: "mt@example.com", password: "password")
    @class1.update!(teacher: @teacher)

    @student1 = User.create!(school: @school, classroom: @class1, name: "미션정책학생1", password: "password")
    @student2 = User.create!(school: @school, classroom: @class2, name: "미션정책학생2", password: "password")
    @superadmin = User.create!(school: @school, name: "총괄", role: :superadmin, email: "sa@example.com", password: "password")

    @published = published_mission("1반 발행 미션")
    @draft = Mission.create!(classroom: @class1, title: "1반 미발행 미션", status: :draft,
                             start_date: Date.current, end_date: Date.current + 7)
  end

  test "student sees own classroom published mission" do
    assert MissionPolicy.new(@student1, @published).show?
  end

  test "student cannot see another classroom's mission" do
    assert_not MissionPolicy.new(@student2, @published).show?
  end

  test "student cannot see own classroom draft (unpublished) mission" do
    assert_not MissionPolicy.new(@student1, @draft).show?
  end

  test "담임 teacher sees own classroom mission (draft included)" do
    assert MissionPolicy.new(@teacher, @published).show?
    assert MissionPolicy.new(@teacher, @draft).show?
  end

  test "superadmin sees any mission" do
    assert MissionPolicy.new(@superadmin, @published).show?
  end

  test "logged-out user is denied" do
    assert_not MissionPolicy.new(nil, @published).show?
  end

  private

  # 발행 미션은 목표≥1 이 검증 필수라 목표를 함께 build 해 저장한다.
  def published_mission(title)
    mission = Mission.new(classroom: @class1, title: title, status: :published,
                          start_date: Date.current, end_date: Date.current + 7)
    mission.mission_goals.build(goal_type: :approved_reports, target_count: 1)
    mission.save!
    mission
  end
end
