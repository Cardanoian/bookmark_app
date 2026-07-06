require "test_helper"

class SchoolTest < ActiveSupport::TestCase
  test "requires a name" do
    school = School.new(name: nil)
    assert_not school.valid?
    assert_includes school.errors[:name], "can't be blank"
  end

  test "neis_code must be unique" do
    School.create!(name: "가나초등학교", neis_code: "N0001")
    duplicate = School.new(name: "다라초등학교", neis_code: "N0001")
    assert_not duplicate.valid?
  end

  test "allows a nil neis_code" do
    School.create!(name: "마바초등학교", neis_code: nil)
    assert School.new(name: "사아초등학교", neis_code: nil).valid?
  end

  test "has_many classrooms and destroys them" do
    school = School.create!(name: "자차초등학교")
    school.classrooms.create!(grade: 3, class_no: 1)
    assert_difference "Classroom.count", -1 do
      school.destroy
    end
  end

  test "has_many users and nullifies them on destroy" do
    school = School.create!(name: "카타초등학교")
    user = User.create!(school: school, name: "학생", password: "password")
    school.destroy
    assert_nil user.reload.school_id
  end
end
