# 뒷이야기 제출 → 비동기 격려형 AI 코멘트(AiReviewJob 미러, 훨씬 가벼움). ai_status 를
# processing→done 으로 전이시키고 ai_comment 를 저장한다. 학생은 무대기(백그라운드).
#
# 무API 폴백 필수: SequelFeedbackService 가 무키/실패 시 규칙기반 격려로 폴백하므로 항상 코멘트를
# 확보한다(네트워크 0·크래시 0 → 항상 done 도달). 예외는 방어적으로만 잡아 :failed 로 전이한다.
class SequelFeedbackJob < ApplicationJob
  queue_as :default

  def perform(sequel_id)
    sequel = BookSequel.find_by(id: sequel_id)
    return unless sequel # 대기 중 뒷이야기가 삭제됐으면 조용히 종료(무해).

    sequel.update!(ai_status: :processing)
    comment = Ai::SequelFeedbackService.new.call(sequel)
    sequel.update!(ai_comment: comment, ai_status: :done)
    broadcast_feedback(sequel)
  rescue StandardError => e
    Rails.logger.error("SequelFeedbackJob failed for sequel #{sequel_id}: #{e.class}: #{e.message}")
    if sequel&.update(ai_status: :failed)
      broadcast_feedback(sequel)
    end
  end

  private

  # 코멘트 완료(또는 실패) → 작성자 play 화면의 그 뒷이야기 AI 코멘트 영역을 실시간 교체한다.
  # play 의 turbo_stream_from sequel 구독(작성자 본인 글만)과 대응. 방송 실패는 흡수(코멘트 커밋 보존).
  def broadcast_feedback(sequel)
    sequel.broadcast_replace_to(
      sequel,
      target: ActionView::RecordIdentifier.dom_id(sequel, :feedback),
      partial: "games/sequel/feedback",
      locals: { sequel: sequel }
    )
  rescue StandardError => e
    Rails.logger.warn("SequelFeedbackJob broadcast failed for sequel #{sequel&.id}: #{e.class}: #{e.message}")
  end
end
