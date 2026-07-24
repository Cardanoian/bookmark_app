require "test_helper"

class ClassroomPolicyTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "학급정책초등학교")
    @other_school = School.create!(name: "다른정책초등학교")

    @classroom1 = Classroom.create!(school: @school, grade: 3, class_no: 1)
    @classroom2 = Classroom.create!(school: @school, grade: 3, class_no: 2)
    @other_classroom = Classroom.create!(school: @other_school, grade: 3, class_no: 1)

    @teacher1 = User.create!(school: @school, classroom: @classroom1, name: "학급교사1", role: :teacher, password: "password")
    @classroom1.update!(teacher: @teacher1)

    @student1 = User.create!(school: @school, classroom: @classroom1, name: "학급학생1", password: "password")
  end

  test "teacher scope resolves only classrooms they teach" do
    resolved = scope_for(@teacher1)
    assert_includes resolved, @classroom1
    assert_not_includes resolved, @classroom2
    assert_not_includes resolved, @other_classroom
  end

  test "student scope resolves only their own classroom" do
    resolved = scope_for(@student1)
    assert_includes resolved, @classroom1
    assert_not_includes resolved, @classroom2
  end

  test "school_admin scope resolves classrooms in their school only" do
    admin = User.create!(school: @school, name: "학급교무", role: :school_admin, password: "password")
    resolved = scope_for(admin)
    assert_includes resolved, @classroom1
    assert_includes resolved, @classroom2
    assert_not_includes resolved, @other_classroom
  end

  test "superadmin scope resolves every classroom" do
    admin = User.create!(name: "학급총괄", role: :superadmin, password: "password")
    resolved = scope_for(admin)
    assert_includes resolved, @classroom1
    assert_includes resolved, @other_classroom
  end

  test "show? enforces classroom boundaries" do
    assert ClassroomPolicy.new(@teacher1, @classroom1).show?
    assert_not ClassroomPolicy.new(@teacher1, @classroom2).show?
    assert ClassroomPolicy.new(@student1, @classroom1).show?
    assert_not ClassroomPolicy.new(@student1, @other_classroom).show?
  end

  private

  def scope_for(user)
    ClassroomPolicy::Scope.new(user, Classroom.all).resolve
  end
end
