require "test_helper"

class CheerPolicyTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "응원정책초")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @teacher = User.create!(school: @school, classroom: @classroom, name: "정책교사", role: :teacher, password: "password")
    @classroom.update!(teacher: @teacher)
    @student = User.create!(school: @school, classroom: @classroom, name: "응원학생", password: "password")

    @report = Report.create!(user: @student, classroom: @classroom, book_title: "정책책", body: "본문")
    @visible = BoardPost.create!(report: @report)

    @hidden_report = Report.create!(user: @student, classroom: @classroom, book_title: "숨김책", body: "본문")
    @hidden = BoardPost.create!(report: @hidden_report, hidden: true)
  end

  test "a student can cheer a visible board post" do
    assert CheerPolicy.new(@student, cheer_on(@visible)).create?
  end

  test "a student cannot cheer a hidden (moderated) board post" do
    assert_not CheerPolicy.new(@student, cheer_on(@hidden)).create?
  end

  test "a non-student cannot cheer even a visible board post" do
    assert_not CheerPolicy.new(@teacher, cheer_on(@visible)).create?
  end

  test "an anonymous user cannot cheer" do
    assert_not CheerPolicy.new(nil, cheer_on(@visible)).create?
  end

  private

  def cheer_on(board_post)
    Cheer.new(board_post: board_post, user: @student)
  end
end
