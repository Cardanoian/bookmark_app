# 독후감 제출 → 비동기 5축 첨삭. ai_status 를 processing→done 으로 전이시키고
# 등급·포인트·유사도를 저장한다. 실패 시 :failed. (§9.4, P3.6)
class AiReviewJob < ApplicationJob
  queue_as :default

  def perform(report)
    report.update!(ai_status: :processing)

    review = Ai::ReviewService.new.call(report)
    result = report.apply_rubric!(review[:rubric])
    report.rubric = review[:rubric].merge(
      praise: review[:praise],
      fix: review[:fix],
      grow: review[:grow]
    )
    report.similarity = Ai::VerifyService.max_similarity(report)
    report.improvement = (report.avg - report.prev_avg).round(2) if report.revision_of_id? && report.prev_avg.present?
    report.ai_status = :done
    report.save!

    report.user.increment!(:points, result[:points])
    broadcast_review_ready(report)
  rescue StandardError => e
    Rails.logger.error("AiReviewJob failed for report #{report&.id}: #{e.class}: #{e.message}")
    report&.update(ai_status: :failed)
  end

  private

  # 첨삭 완료 → 교사 검토 큐에 행을 추가한다(제출→검토 큐 실시간, §10, P3.9).
  def broadcast_review_ready(report)
    report.broadcast_append_to(
      [ report.classroom, :review_queue ],
      target: "review_queue",
      partial: "teacher/reviews/report_row",
      locals: { report: report }
    )
  end
end
