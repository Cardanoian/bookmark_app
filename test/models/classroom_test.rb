require "test_helper"

class ClassroomTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "테스트초등학교")
  end

  test "belongs to a school" do
    classroom = Classroom.new(school: @school, grade: 3, class_no: 1)
    assert_equal @school, classroom.school
  end

  test "class_no is unique within a school and grade" do
    Classroom.create!(school: @school, grade: 3, class_no: 1)
    duplicate = Classroom.new(school: @school, grade: 3, class_no: 1)
    assert_not duplicate.valid?
  end

  test "allows the same class_no in a different grade" do
    Classroom.create!(school: @school, grade: 3, class_no: 1)
    assert Classroom.new(school: @school, grade: 4, class_no: 1).valid?
  end

  test "allows the same class_no in a different school" do
    other = School.create!(name: "다른초등학교")
    Classroom.create!(school: @school, grade: 3, class_no: 1)
    assert Classroom.new(school: other, grade: 3, class_no: 1).valid?
  end

  test "label formats grade and class_no" do
    classroom = Classroom.new(grade: 3, class_no: 2)
    assert_equal "3학년 2반", classroom.label
  end

  test "injects default rubric_config on create" do
    classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    assert_equal Classroom::DEFAULT_RUBRIC_WEIGHTS.stringify_keys, classroom.rubric_config["weights"]
    assert_nil classroom.rubric_config["emphasis"]
    assert_nil classroom.rubric_config["label"]
  end

  test "does not overwrite an explicitly provided rubric_config" do
    custom = { "weights" => { "content" => 3 }, "emphasis" => "content", "label" => "감상 강화" }
    classroom = Classroom.create!(school: @school, grade: 5, class_no: 2, rubric_config: custom)
    assert_equal custom, classroom.rubric_config
  end

  test "rubric_weights returns symbolized default weights" do
    classroom = Classroom.create!(school: @school, grade: 5, class_no: 3)
    assert_equal Classroom::DEFAULT_RUBRIC_WEIGHTS, classroom.rubric_weights
  end

  test "rubric_emphasis reads from the config" do
    custom = { "weights" => Classroom::DEFAULT_RUBRIC_WEIGHTS.stringify_keys, "emphasis" => "emotion", "label" => nil }
    classroom = Classroom.create!(school: @school, grade: 5, class_no: 4, rubric_config: custom)
    assert_equal "emotion", classroom.rubric_emphasis
  end
end
