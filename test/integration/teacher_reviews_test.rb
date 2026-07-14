require "test_helper"

class TeacherReviewsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @school = School.create!(name: "검토통합학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @teacher = User.create!(school: @school, classroom: @classroom, name: "검토담임", role: :teacher, password: "password", approved: true)
    @classroom.update!(teacher: @teacher)

    @other_classroom = Classroom.create!(school: @school, grade: 5, class_no: 2)
    @other_teacher = User.create!(school: @school, classroom: @other_classroom, name: "다른담임", role: :teacher, password: "password", approved: true)
    @other_classroom.update!(teacher: @other_teacher)

    @student = User.create!(school: @school, classroom: @classroom, name: "검토학생", password: "password")
    @report = Report.create!(
      user: @student, classroom: @classroom, book_title: "책", body: "본문",
      ai_status: :done, avg: 3.0, level: "B", reviewed: false
    )
  end

  test "queue lists the담임's pending classroom reports" do
    login_as @teacher
    get teacher_reviews_path
    assert_response :success
    assert_match @student.name, response.body
  end

  test "a student is forbidden from the review queue" do
    login_as @student
    get teacher_reviews_path
    assert_response :forbidden
  end

  test "a non-담임 teacher is forbidden from another classroom's report" do
    login_as @other_teacher
    get teacher_review_path(@report)
    assert_response :forbidden
  end

  test "update saves the teacher rubric adjustment and comment" do
    login_as @teacher
    patch teacher_review_path(@report), params: {
      report: { teacher_comment: "잘했어요",
                teacher_rubric: { content: 5, emotion: 4, life: 4, structure: 3, spelling: 4 } }
    }

    @report.reload
    assert_equal "잘했어요", @report.teacher_comment
    assert_equal 5, @report.teacher_rubric["content"]
  end

  test "approve marks the report reviewed and broadcasts to the student" do
    login_as @teacher

    broadcasts = capture_turbo_stream_broadcasts([ @student, :reports ]) do
      post approve_teacher_review_path(@report)
    end

    @report.reload
    assert @report.reviewed?
    assert_not_nil @report.reviewed_at
    assert_equal 1, broadcasts.size
    assert_equal "replace", broadcasts.first["action"]
  end

  test "approving a report grants the student's reading badge (approval fires the badge cascade)" do
    seed_badges!
    login_as @teacher

    assert_not_includes @student.badges.pluck(:key), "first"
    post approve_teacher_review_path(@report)

    assert_includes @student.badges.reload.pluck(:key), "first",
      "승인 시점에 first(독후감 1편) 뱃지가 부여돼야 한다"
  end

  test "verify exposes the similarity signal to the teacher" do
    login_as @teacher
    post verify_teacher_review_path(@report)
    assert_response :success
    assert_match "진위", response.body
  end

  test "batch_approve approves all selected reports" do
    other = Report.create!(user: @student, classroom: @classroom, book_title: "책2", ai_status: :done, reviewed: false)
    login_as @teacher

    post batch_approve_teacher_reviews_path, params: { report_ids: [ @report.id, other.id ] }

    assert @report.reload.reviewed?
    assert other.reload.reviewed?
  end

  private
end
