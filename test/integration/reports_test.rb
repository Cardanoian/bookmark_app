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

  test "student deletes own report from the list" do
    report = Report.create!(user: @student, classroom: @classroom, book_title: "지울 글", body: "본문")
    login_as @student

    get reports_path
    assert_select "form[action=?][method=post]", report_path(report) do
      assert_select "input[name=_method][value=delete]", 1
      assert_select "button", text: "삭제"
    end

    assert_difference("Report.count", -1) do
      delete report_path(report)
    end
    assert_redirected_to reports_path
  end

  test "deleting a pending report safely discards its queued review job" do
    report = Report.create!(user: @student, classroom: @classroom, book_title: "대기 중인 글", body: "본문")
    login_as @student
    AiReviewJob.perform_later(report)

    delete report_path(report)

    assert_nothing_raised { perform_enqueued_jobs }
  end

  test "student cannot delete another student's report" do
    report = Report.create!(user: @other, classroom: @classroom, book_title: "남의 글", body: "본문")
    login_as @student

    assert_no_difference("Report.count") do
      delete report_path(report)
    end
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

  # #misc: 고쳐쓰기 초기 상태는 원본과 본문이 동일하므로 재첨삭 AI 를 호출하지 않는다(낭비 방지).
  # 대신 원본 첨삭 결과를 이어받아 done 으로 시작한다.
  test "revise does not re-review an identical body and carries the parent's review forward" do
    original = Report.create!(
      user: @student, classroom: @classroom, book_title: "원본", body: "같은 본문",
      avg: 4.2, level: "A", ai_status: :done,
      rubric: { "content" => 5, "emotion" => 4, "life" => 4, "structure" => 4, "spelling" => 4 }
    )
    login_as @student

    assert_no_enqueued_jobs only: AiReviewJob do
      post revise_report_path(original)
    end

    revision = @student.reports.where.not(id: original.id).order(:created_at).last
    assert revision.done?, "동일 본문은 재첨삭을 건너뛰고 부모 결과를 이어받아 done 으로 시작"
    assert_equal original.rubric, revision.rubric
    assert_equal original.avg, revision.prev_avg
  end

  # 학생이 본문을 실제로 고쳐 저장하면 그때 재첨삭이 예약된다(resubmit? 가드).
  test "editing a revision body re-enqueues review" do
    original = Report.create!(user: @student, classroom: @classroom, book_title: "원본", body: "원래 본문", avg: 3.0, ai_status: :done)
    login_as @student
    post revise_report_path(original)
    revision = @student.reports.where.not(id: original.id).order(:created_at).last

    assert_enqueued_with job: AiReviewJob do
      patch report_path(revision), params: { report: { body: "완전히 새로 고쳐 쓴 본문이에요." } }
    end
  end

  # 수정/고쳐쓰기 단일화(#misc): 상세 화면에는 고쳐쓰기만 노출하고 제자리 '수정' 링크는 제거한다.
  test "report show exposes 고쳐쓰기 but no longer the in-place 수정 link" do
    report = Report.create!(user: @student, classroom: @classroom, book_title: "책", body: "본문", ai_status: :done)
    login_as @student

    get report_path(report)
    assert_response :success
    assert_select "form[action=?]", revise_report_path(report), 1, "고쳐쓰기 버튼(button_to)이 있어야 한다"
    assert_select "a[href=?]", edit_report_path(report), count: 0, message: "제자리 수정 링크는 제거되어야 한다"
  end

  # 재첨삭 결과가 새로고침 없이 보이도록 학생 상세 화면은 report 스트림을 구독한다.
  test "report show subscribes to the report stream for live review updates" do
    report = Report.create!(user: @student, classroom: @classroom, book_title: "책", body: "본문", ai_status: :pending)
    login_as @student

    get report_path(report)
    assert_response :success
    assert_select "turbo-cable-stream-source", 1, "상세 화면이 라이브 갱신을 구독해야 한다"
  end

  # 첨삭 완료 시 학생 상세 영역을 실시간 교체하는 방송이 report 스트림으로 나간다.
  test "completing a review broadcasts a live replace to the report's own stream" do
    report = Report.create!(user: @student, classroom: @classroom, book_title: "책",
      body: "나는 우리의 삶을 떠올리며 감동을 느꼈다.", ai_status: :pending)

    broadcasts = capture_turbo_stream_broadcasts(report) do
      perform_enqueued_jobs { AiReviewJob.perform_later(report) }
    end

    assert report.reload.done?
    assert(broadcasts.any? { |stream| stream["action"] == "replace" }, "재첨삭 완료 시 replace 방송이 있어야 한다")
  end

  # dirty-check 배선: 고쳐쓰기(기존 글) 폼은 본문이 달라져야 저장이 눌리도록 report-edit 컨트롤러를 단다.
  test "revision edit form wires the report-edit dirty-check controller" do
    original = Report.create!(user: @student, classroom: @classroom, book_title: "책", body: "원본 본문", ai_status: :done)
    login_as @student
    post revise_report_path(original)
    revision = @student.reports.where.not(id: original.id).order(:created_at).last

    get edit_report_path(revision)
    assert_response :success
    assert_select "form[data-controller='report-edit']", 1
    assert_select "textarea[data-report-edit-target='body']", 1
    assert_select "input[type=submit][data-report-edit-target='submit']", 1
  end

  # 새 글 폼은 위저드 초안을 그대로 제출할 수 있어야 하므로 dirty-check 를 걸지 않는다.
  test "new report form is not gated by the dirty-check controller" do
    login_as @student
    get new_report_path
    assert_response :success
    assert_select "form[data-controller='report-edit']", count: 0
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

  test "reports index paginates the student's own reports into 20-per-page slices" do
    25.times { |i| Report.create!(user: @student, classroom: @classroom, book_title: "책#{format('%02d', i)}") }
    login_as @student

    get reports_path
    assert_response :success
    assert_select "article", 20
    assert_match "다음", response.body

    get reports_path(page: 2)
    assert_response :success
    assert_select "article", 5
    assert_match "이전", response.body
  end

  private
end
