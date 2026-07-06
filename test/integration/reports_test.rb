require "test_helper"

class ReportsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @school = School.create!(name: "독후감통합학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @teacher = User.create!(school: @school, classroom: @classroom, name: "통합담임", role: :teacher, password: "password")
    @classroom.update!(teacher: @teacher)
    @student = User.create!(school: @school, classroom: @classroom, name: "통합학생", password: "password")
    @other = User.create!(school: @school, classroom: @classroom, name: "다른통합학생", password: "password")
  end

  test "student creating a report enqueues review and stays pending" do
    login_as @student

    assert_enqueued_with(job: AiReviewJob) do
      post reports_path, params: { report: { book_title: "책", body: "나는 이 책을 읽었다.", input_mode: "keyboard" } }
    end

    report = @student.reports.order(:created_at).last
    assert_not_nil report
    assert report.pending?
    assert_redirected_to report_path(report)
  end

  test "a student cannot view another student's report" do
    report = Report.create!(user: @other, classroom: @classroom, book_title: "남의 글")
    login_as @student
    get report_path(report)
    assert_response :forbidden
  end

  test "show renders the 5축 rubric after the offline review job runs" do
    login_as @student
    perform_enqueued_jobs do
      post reports_path, params: { report: { book_title: "책", body: "나는 우리의 삶을 생각하며 감동을 느꼈다." } }
    end

    report = @student.reports.order(:created_at).last
    assert report.reload.done?

    get report_path(report)
    assert_response :success
    assert_match "5축", response.body
  end

  test "a teacher (non-student) cannot create a report" do
    login_as @teacher
    post reports_path, params: { report: { book_title: "책", body: "본문" } }
    assert_response :forbidden
  end

  test "revise creates a linked revision that records prev_avg" do
    original = Report.create!(user: @student, classroom: @classroom, book_title: "원본", body: "짧은 글", avg: 3.5)
    login_as @student

    post revise_report_path(original)

    revision = @student.reports.where.not(id: original.id).order(:created_at).last
    assert_equal original.id, revision.revision_of_id
    assert_equal original.avg, revision.prev_avg
    assert_redirected_to edit_report_path(revision)
  end

  test "completing a review appends a row to the classroom review queue" do
    login_as @student

    broadcasts = capture_turbo_stream_broadcasts([ @classroom, :review_queue ]) do
      perform_enqueued_jobs do
        post reports_path, params: { report: { book_title: "책", body: "나는 우리의 삶을 떠올렸다." } }
      end
    end

    assert_operator broadcasts.size, :>=, 1
    assert_equal "append", broadcasts.first["action"]
  end

  private

  def login_as(user)
    post session_path, params: {
      school_id: user.school_id, classroom_id: user.classroom_id,
      name: user.name, password: "password"
    }
  end
end
