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

    # 멱등 포인트: 이 독후감이 이미 지급한 것과의 차액만 반영해 재첨삭 파밍을 막는다.
    previously_awarded = report.points_awarded.to_i
    delta = result[:points].to_i - previously_awarded
    report.points_awarded = result[:points].to_i
    report.ai_status = :done
    report.save!

    award_points_delta(report.user, delta)
    broadcast_review_ready(report)
  rescue StandardError => e
    Rails.logger.error("AiReviewJob failed for report #{report&.id}: #{e.class}: #{e.message}")
    report&.update(ai_status: :failed)
  end

  private

  # 포인트 차액 적용. 양수는 award_points 로 적립해 뱃지·진화·랭킹 후크를 태우고,
  # 음수(재첨삭으로 등급 하락)는 잔액을 조정한 뒤 뱃지를 재계산(멱등)한다.
  def award_points_delta(user, delta)
    if delta.positive?
      user.award_points(delta, reason: "report_review")
    elsif delta.negative?
      user.update!(points: [ user.points + delta, 0 ].max)
      user.refresh_badges!
    end
  end

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
