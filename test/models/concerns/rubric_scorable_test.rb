require "test_helper"

class RubricScorableTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "루브릭학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @user = User.create!(school: @school, classroom: @classroom, name: "루브릭학생", password: "password")
  end

  test "perfect scores earn an A worth 30 points" do
    result = RubricScorable.score_rubric({ content: 5, emotion: 5, life: 5, structure: 5, spelling: 5 })
    assert_equal "A", result[:level]
    assert_equal 30, result[:points]
    assert_equal 5.0, result[:avg]
  end

  test "avg 4.0 with life 4 is the A boundary" do
    result = RubricScorable.score_rubric({ content: 4, emotion: 4, life: 4, structure: 4, spelling: 4 })
    assert_equal "A", result[:level]
    assert_equal 4.0, result[:avg]
  end

  test "high avg but life below 4 falls to B" do
    result = RubricScorable.score_rubric({ content: 5, emotion: 5, life: 3, structure: 5, spelling: 5 })
    assert_equal "B", result[:level]
    assert_equal 20, result[:points]
  end

  test "avg exactly 2.5 is the B boundary" do
    result = RubricScorable.score_rubric({ content: 2.5, emotion: 2.5, life: 2.5, structure: 2.5, spelling: 2.5 })
    assert_equal 2.5, result[:avg]
    assert_equal "B", result[:level]
  end

  test "avg just below 2.5 is a C worth 10 points" do
    result = RubricScorable.score_rubric({ content: 2, emotion: 3, life: 1, structure: 2, spelling: 2 })
    assert_equal "C", result[:level]
    assert_equal 10, result[:points]
  end

  test "a missing axis is treated as zero" do
    result = RubricScorable.score_rubric({ content: 5, emotion: 5 })
    assert_equal 2.0, result[:avg]
    assert_equal "C", result[:level]
  end

  test "weights change the weighted average and the resulting level" do
    rubric = { content: 5, emotion: 1, life: 1, structure: 1, spelling: 1 }
    equal = RubricScorable.score_rubric(rubric)
    weighted = RubricScorable.score_rubric(rubric, weights: { content: 10, emotion: 1, life: 1, structure: 1, spelling: 1 })

    assert_equal "C", equal[:level]
    assert_equal "B", weighted[:level]
    assert_operator weighted[:avg], :>, equal[:avg]
  end

  test "apply_rubric! populates avg/level/rubric without saving" do
    report = build_report
    result = report.apply_rubric!({ content: 5, emotion: 5, life: 5, structure: 5, spelling: 5 })

    assert_equal "A", report.level
    assert_equal 5.0, report.avg
    assert_equal({ "content" => 5, "emotion" => 5, "life" => 5, "structure" => 5, "spelling" => 5 }, report.rubric)
    assert_equal 30, result[:points]
    assert report.new_record?
  end

  test "apply_rubric! respects the classroom's custom weights" do
    @classroom.update!(rubric_config: {
      "weights" => { "content" => 10, "emotion" => 1, "life" => 1, "structure" => 1, "spelling" => 1 }
    })
    report = build_report
    report.apply_rubric!({ content: 5, emotion: 1, life: 1, structure: 1, spelling: 1 })

    assert_equal "B", report.level
  end

  private

  def build_report(attrs = {})
    Report.new({ user: @user, classroom: @classroom, book_title: "기본 제목" }.merge(attrs))
  end
end
