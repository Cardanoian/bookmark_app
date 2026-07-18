require "test_helper"

# 첫 첨삭 가드(first_review?, 계획 §4.2) — OCR 초안처럼 아직 rubric 이 없는(revise 아닌)
# 신규 글은 본문을 바꾸지 않고 그대로 제출해도 AI 첨삭이 예약돼야 한다(결함① 해결).
# revise 초안(rubric 상속)은 기존대로 동일 본문 재첨삭을 스킵하고, 본문이 비어 있으면
# (OCR 완료 전 조기 제출 레이스) 첨삭을 예약하지 않는다.
class ReportFirstReviewTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @school = School.create!(name: "첫첨삭학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @student = User.create!(school: @school, classroom: @classroom, name: "첫첨삭학생", password: "password")
  end

  # AC5 — 본인 OCR draft(body 채움, ai_status done, rubric 공란, revision_of nil).
  test "submitting an unmodified OCR draft still enqueues the first review" do
    report = Report.create!(user: @student, classroom: @classroom, book_title: "사진 책",
      input_mode: :ocr, body: "사진에서 읽어낸 본문", ai_status: :done)
    login_as @student

    assert_enqueued_with(job: AiReviewJob) do
      patch report_path(report), params: { report: { body: report.body } }
    end

    assert report.reload.pending?
  end

  # 회귀 — revise 초안은 revision_of_id 가 있어 first_review? 대상이 아니므로
  # 동일 본문 재제출 시 기존대로 재첨삭을 스킵한다.
  test "submitting an unmodified revision draft does not re-enqueue review" do
    original = Report.create!(user: @student, classroom: @classroom, book_title: "원본", body: "같은 본문",
      avg: 4.0, level: "B", ai_status: :done,
      rubric: { "content" => 4, "emotion" => 4, "life" => 4, "structure" => 4, "spelling" => 4 })
    login_as @student
    post revise_report_path(original)
    revision = @student.reports.where.not(id: original.id).order(:created_at).last

    assert_no_enqueued_jobs only: AiReviewJob do
      patch report_path(revision), params: { report: { body: revision.body } }
    end
  end

  # 레이스 가드(Critic minor#1) — OCR 이 아직 본문을 채우기 전에 제출되면(빈 본문)
  # 첨삭을 예약하지 않는다(빈 첨삭 방지).
  test "submitting an OCR draft with a blank body does not enqueue a review" do
    report = Report.create!(user: @student, classroom: @classroom, book_title: "사진 책",
      input_mode: :ocr, body: "")
    login_as @student

    assert_no_enqueued_jobs only: AiReviewJob do
      patch report_path(report), params: { report: { body: "" } }
    end
  end
end
