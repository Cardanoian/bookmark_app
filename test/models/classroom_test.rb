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
end
