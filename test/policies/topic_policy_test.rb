require "test_helper"

# P5.4 — 토론방 스코프 경계. 학생/교사는 자기 학급-스코프 + 자기 학교-스코프만 본다.
class TopicPolicyTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "토론정책초")
    @other_school = School.create!(name: "다른정책초")
    @class1 = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @class2 = Classroom.create!(school: @school, grade: 5, class_no: 2)
    @student1 = User.create!(school: @school, classroom: @class1, name: "정책학생1", password: "password")
    @student2 = User.create!(school: @school, classroom: @class2, name: "정책학생2", password: "password")
    @other_student = User.create!(school: @other_school, name: "타교학생", password: "password")

    @class1_topic = Topic.create!(scope: :classroom, classroom: @class1, title: "1반 토론")
    @class2_topic = Topic.create!(scope: :classroom, classroom: @class2, title: "2반 토론")
    @school_topic = Topic.create!(scope: :school, school: @school, title: "학교 토론")
  end

  def scope_for(user)
    TopicPolicy::Scope.new(user, Topic.all).resolve
  end

  test "student sees their own classroom-scope topic" do
    assert_includes scope_for(@student1), @class1_topic
  end

  test "student cannot see another classroom's classroom-scope topic" do
    assert_not_includes scope_for(@student1), @class2_topic
  end

  test "student sees their school-scope topic" do
    assert_includes scope_for(@student1), @school_topic
  end

  test "student from another school cannot see the school-scope topic" do
    assert_not_includes scope_for(@other_student), @school_topic
  end

  test "show? enforces the classroom boundary" do
    assert TopicPolicy.new(@student1, @class1_topic).show?
    assert_not TopicPolicy.new(@student1, @class2_topic).show?
  end

  test "hidden topics are excluded from the scope" do
    @class1_topic.update!(hidden: true)
    assert_not_includes scope_for(@student1), @class1_topic
  end
end
