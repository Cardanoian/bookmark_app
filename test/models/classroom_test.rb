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

  # --- 학년도(academic_year) ---

  test "current_academic_year treats January and February as the previous school year" do
    assert_equal 2026, Classroom.current_academic_year(Date.new(2027, 1, 15)), "1월 → 전년도"
    assert_equal 2026, Classroom.current_academic_year(Date.new(2027, 2, 28)), "2월 → 전년도"
    assert_equal 2027, Classroom.current_academic_year(Date.new(2027, 3, 1)), "3월 → 당해년도(새 학년도 시작)"
    assert_equal 2026, Classroom.current_academic_year(Date.new(2026, 12, 31)), "12월 → 당해년도"
  end

  test "current_academic_year uses the Korea time zone for the boundary" do
    # UTC 로는 2월(→2026)이지만 KST 로는 3월 1일 새벽(→2027)인 순간. 서버 KST 계산을 검증한다.
    travel_to(Time.utc(2027, 2, 28, 20, 0, 0)) do
      assert_equal 2027, Classroom.current_academic_year
    end
  end

  test "defaults academic_year to the current school year on create" do
    classroom = Classroom.create!(school: @school, grade: 2, class_no: 5)
    assert_equal Classroom.current_academic_year, classroom.academic_year
  end

  test "an explicit academic_year overrides the default" do
    classroom = Classroom.create!(school: @school, academic_year: 2030, grade: 2, class_no: 6)
    assert_equal 2030, classroom.academic_year
  end

  test "allows the same grade and class_no in a different academic year" do
    Classroom.create!(school: @school, academic_year: 2026, grade: 3, class_no: 1)
    assert Classroom.new(school: @school, academic_year: 2027, grade: 3, class_no: 1).valid?,
      "학년도가 다르면 같은 학년·반이 공존할 수 있어야 한다"
  end

  test "rejects a duplicate grade and class_no within the same academic year" do
    Classroom.create!(school: @school, academic_year: 2026, grade: 3, class_no: 1)
    duplicate = Classroom.new(school: @school, academic_year: 2026, grade: 3, class_no: 1)
    assert_not duplicate.valid?
  end

  test "requires a plausible academic_year" do
    assert_not Classroom.new(school: @school, academic_year: 1999, grade: 3, class_no: 1).valid?
    assert_not Classroom.new(school: @school, academic_year: 3000, grade: 3, class_no: 1).valid?
  end

  test "label_with_year prefixes the academic year while label stays unchanged" do
    classroom = Classroom.new(academic_year: 2026, grade: 3, class_no: 1)
    assert_equal "3학년 1반", classroom.label
    assert_equal "2026학년도 3학년 1반", classroom.label_with_year
  end
end
