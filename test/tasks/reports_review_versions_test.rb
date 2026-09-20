require "test_helper"
require "rake"

# reports:requeue_reviews / reports:audit_review_versions 스모크(BUG_FIX_PLAN §4.2-5·§7.2·§7.3).
# 확정되지 않은 **현재 버전**만 같은 버전으로 다시 예약하고(이미 확정한 글은 다시 채점하지 않는다),
# 기본은 dry-run 이며, 점검 태스크는 아무것도 바꾸지 않는다.
class ReportsReviewVersionsTaskTest < ActiveJob::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("reports:requeue_reviews")
    @school = School.create!(name: "재예약초")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @student = User.create!(school: @school, classroom: @classroom, name: "재예약학생", password: "password")

    @pending = create_report(ai_status: :pending, submitted_at: Time.current, review_version: 3, completed_review_version: 2)
    @processing = create_report(ai_status: :processing, submitted_at: Time.current, review_version: 1)
    @failed = create_report(ai_status: :failed, submitted_at: Time.current, review_version: 1)
    @done = create_report(**review_ready_attributes)
    @draft = create_report(ai_status: :pending)
  end

  test "기본은 dry-run 이라 아무것도 예약하지 않는다" do
    output = nil
    assert_no_enqueued_jobs(only: AiReviewJob) { output = run_task("reports:requeue_reviews") }

    assert_match "대상 2건", output
    assert_match "dry-run", output
    assert @processing.reload.processing?
  end

  test "APPLY=1 은 대기·처리 중인 현재 버전만 같은 버전으로 예약한다" do
    with_env("APPLY" => "1") { run_task("reports:requeue_reviews") }

    assert_equal({ @pending.id => 3, @processing.id => 1 }, enqueued_versions)
    assert @processing.reload.pending?
    assert @failed.reload.failed?, "실패한 글은 FAILED=1 일 때만 포함한다"
    assert_equal [ 3, 2 ], @pending.reload.values_at(:review_version, :completed_review_version), "버전을 올리지 않는다"
  end

  test "FAILED=1 은 실패한 글도 포함하고, 확정된 글과 초안은 어떤 경우에도 예약하지 않는다" do
    with_env("APPLY" => "1", "FAILED" => "1") { run_task("reports:requeue_reviews") }

    assert_equal [ @pending.id, @processing.id, @failed.id ].sort, enqueued_versions.keys.sort
    assert @failed.reload.pending?
    assert @done.reload.done?
    assert @draft.reload.draft?
  end

  test "예약된 작업을 돌리면 결과와 보상이 한 번씩 확정된다" do
    with_env("APPLY" => "1", "FAILED" => "1") { 2.times { run_task("reports:requeue_reviews") } } # 두 번 돌려도

    perform_enqueued_jobs

    [ @pending, @processing, @failed ].each { |report| assert report.reload.review_ready? }
    assert_equal [ @pending, @processing, @failed ].sum { |report| report.reload.points_awarded }, @student.reload.points
  end

  # 제출 버전은 1 부터다. 0 으로 확정하면 승인도 재요청도 못 하는 글이 되므로 예약하지 않고 점검 목록에만 올린다.
  test "제출됐는데 버전이 0 인 글은 예약하지 않고 audit 이 목록화한다" do
    broken = create_report(ai_status: :pending, submitted_at: Time.current, review_version: 0)

    with_env("APPLY" => "1") { run_task("reports:requeue_reviews") }
    assert_not_includes enqueued_versions.keys, broken.id

    assert_no_difference -> { @student.reload.points } do
      AiReviewJob.perform_now(broken, expected_review_version: 0)
    end
    assert_nil broken.reload.completed_review_version
    assert_not AiReviewJob.enqueue_for(broken, 0), "버전 0 으로는 예약하지 않는다"

    assert_match "제출 버전이 0 인 글 1건 — report=#{broken.id}", run_task("reports:audit_review_versions")
  end

  test "audit 은 승인됐지만 완성된 첨삭이 없는 글을 읽기 전용으로 목록화한다" do
    legacy = create_report(ai_status: :done, submitted_at: Time.current, reviewed: true, review_version: 1) # 첨삭 없이 승인된 옛 글
    fine = create_report(**review_ready_attributes(reviewed: true, reviewed_at: Time.current))
    before = Report.order(:id).pluck(:id, :updated_at, :reviewed, :ai_status)

    output = run_task("reports:audit_review_versions")

    assert_match "1건", output
    assert_match "report=#{legacy.id} ", output
    assert_no_match "report=#{fine.id} ", output
    assert_no_match @student.name, output, "학생 이름은 출력하지 않는다"
    assert_equal before, Report.order(:id).pluck(:id, :updated_at, :reviewed, :ai_status), "아무것도 바꾸지 않는다"
  end

  private

  def create_report(**attrs)
    Report.create!(user: @student, classroom: @classroom, book_title: "재예약책",
                   body: "나는 이 책을 읽고 우리의 삶을 생각했다. 감동을 느꼈다.", **attrs)
  end

  def run_task(name)
    Rake::Task[name].reenable
    capture_io { Rake::Task[name].invoke }.first
  end

  def with_env(values)
    originals = values.keys.to_h { |key| [ key, ENV[key] ] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    originals.each { |key, value| ENV[key] = value }
  end

  # { report_id => expected_review_version }
  def enqueued_versions
    enqueued_jobs.select { |job| job["job_class"] == "AiReviewJob" }.to_h do |job|
      gid, options = job["arguments"]
      [ gid["_aj_globalid"].split("/").last.to_i, options["expected_review_version"] ]
    end
  end
end
