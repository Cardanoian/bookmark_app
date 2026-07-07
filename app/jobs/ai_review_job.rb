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
      # award_points 가 원자 증가(update_counters)+reload+후크를 담당 — 여기서 이중 적용하지 않는다.
      user.award_points(delta, reason: "report_review")
    elsif delta.negative?
      # 음수 델타는 0 바닥의 원자 차감으로 비원자 read-modify-write 경합을 없앤다.
      # (포인트 임계 뱃지 조건은 없어 refresh_badges! 전 reload 는 필수는 아니나, 최신값 기준으로 재계산하도록 유지.)
      User.where(id: user.id).update_all("points = MAX(points - #{delta.abs.to_i}, 0)")
      user.reload
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
