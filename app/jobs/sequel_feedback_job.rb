# 뒷이야기 제출 → 비동기 격려형 AI 코멘트(AiReviewJob 미러, 훨씬 가벼움). ai_status 를
# processing→done 으로 전이시키고 ai_comment 를 저장한다. 학생은 무대기(백그라운드).
# 저장한 코멘트는 담임이 승인해야 학생에게 보인다(BookSequel#comment_visible?) — 완료 방송은 학생 화면을
# "읽는 중"에서 "선생님이 확인하고 있어요"로 바꿀 뿐 코멘트를 싣지 않는다.
#
# 무API 폴백 필수: SequelFeedbackService 가 무키/실패 시 규칙기반 격려로 폴백하므로 항상 코멘트를
# 확보한다(네트워크 0·크래시 0 → 항상 done 도달). 예외는 방어적으로만 잡아 :failed 로 전이한다.
class SequelFeedbackJob < ApplicationJob
  queue_as :default

  def perform(sequel_id)
    sequel = BookSequel.find_by(id: sequel_id)
    return unless sequel # 대기 중 뒷이야기가 삭제됐으면 조용히 종료(무해).

    # 담임이 이미 승인한 글은 다시 쓰지 않는다 — 고치지 않고 승인한 글이면 새 ai_comment 가 담임이 읽지
    # 않은 채 그대로 학생에게 보인다(워커가 죽어 잡이 다시 도는 경우 등). 확인과 전이를 한 UPDATE 로 해서
    # 승인과의 경합도 막는다: 승인이 먼저 커밋되면 0행, 이 전이가 먼저면 승인이 processing 을 보고 거절한다.
    claimed = BookSequel.where(id: sequel.id, reviewed_at: nil)
                        .update_all(ai_status: BookSequel.ai_statuses[:processing], updated_at: Time.current)
    return if claimed.zero?

    sequel.reload
    comment = Ai::SequelFeedbackService.new.call(sequel)
    sequel.update!(ai_comment: comment, ai_status: :done)
    sequel.broadcast_feedback_refresh
  rescue StandardError => e
    Rails.logger.error("SequelFeedbackJob failed for sequel #{sequel_id}: #{e.class}: #{e.message}")
    sequel.broadcast_feedback_refresh if sequel&.update(ai_status: :failed)
  end
end
