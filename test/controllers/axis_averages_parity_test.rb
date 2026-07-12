require "test_helper"

# 전교 5축 집계(#3)를 인메모리 Ruby 루프에서 SQL(json_extract AVG)로 대체했다.
# 두 경로(Relation→SQL / Array→인메모리)가 같은 값을 내는지 parity 를 고정한다.
# axis_averages 는 base 컨트롤러 공용 private 메서드라 인스턴스에서 send 로 호출한다.
class AxisAveragesParityTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "집계학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @student = User.create!(school: @school, classroom: @classroom, name: "집계학생", password: "password")
  end

  def make_report(rubric)
    Report.create!(user: @student, classroom: @classroom, book_title: "책", rubric: rubric)
  end

  # SchoolAdmin·Teacher 두 base 컨트롤러가 동일 구현을 공유하므로 둘 다 검증.
  def controllers
    [ SchoolAdmin::StatsController.new, Teacher::DashboardsController.new ]
  end

  def assert_parity(relation)
    controllers.each do |ctrl|
      sql = ctrl.send(:axis_averages, relation)
      mem = ctrl.send(:axis_averages, relation.to_a)
      assert_equal mem, sql, "#{ctrl.class}: SQL 집계가 인메모리 집계와 동일해야 한다"
    end
  end

  test "parity for full rubrics" do
    make_report({ "content" => 5, "emotion" => 4, "life" => 3, "structure" => 2, "spelling" => 1 })
    make_report({ "content" => 1, "emotion" => 2, "life" => 3, "structure" => 4, "spelling" => 5 })
    assert_parity(Report.where(classroom_id: @classroom.id))
  end

  # 누락축(→0) + rubric 없는 리포트(→집계 제외) 혼재에서도 parity.
  test "parity with a partial rubric (missing axis) and an unreviewed report" do
    make_report({ "content" => 4, "emotion" => 4 }) # life/structure/spelling 누락 → 0
    make_report({ "content" => 2, "emotion" => 2, "life" => 2, "structure" => 2, "spelling" => 2 })
    make_report(nil) # rubric 없음 → 집계 제외(분모 미포함)
    assert_parity(Report.where(classroom_id: @classroom.id))
  end

  # 채점 리포트가 하나도 없으면 두 경로 모두 축별 0.0.
  test "parity when no report has a rubric yields all zeros" do
    make_report(nil)
    relation = Report.where(classroom_id: @classroom.id)
    controllers.each do |ctrl|
      result = ctrl.send(:axis_averages, relation)
      assert_equal ReadingDomain::RUBRIC_AXES.index_with { 0.0 }, result
    end
    assert_parity(relation)
  end

  # 실제 SQL 평균값 확인(누락축 0 반영): content = (5+1)/2 = 3.0.
  test "sql aggregation computes the documented average" do
    make_report({ "content" => 5, "emotion" => 0, "life" => 0, "structure" => 0, "spelling" => 0 })
    make_report({ "content" => 1, "emotion" => 0, "life" => 0, "structure" => 0, "spelling" => 0 })
    result = SchoolAdmin::StatsController.new.send(:axis_averages, Report.where(classroom_id: @classroom.id))
    assert_equal 3.0, result[:content]
  end
end
