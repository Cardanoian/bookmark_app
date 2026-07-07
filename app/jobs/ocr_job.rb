# 사진 업로드 → 비동기 손글씨 OCR → report.body 초안. 키 없으면 Unavailable, API 호출
# 실패·빈 응답이면 GeminiClient::ApiError → 어느 쪽이든 :failed 로 전이시켜 pending 에
# 영구히 묶이지 않게 한다. (§9.3, P3.4)
class OcrJob < ApplicationJob
  queue_as :default

  def perform(report)
    text = Ai::OcrService.new.call(report.photo.blob)
    report.update!(body: text, ai_status: :done)
    broadcast_ocr_ready(report)
  rescue Ai::OcrService::Unavailable, Ai::GeminiClient::ApiError => e
    Rails.logger.error("OcrJob failed for report #{report&.id}: #{e.class}: #{e.message}")
    report&.update(ai_status: :failed)
  end

  private

  # OCR 초안 → 작성자의 에디터 본문을 교체한다(사진→텍스트 실시간, P3.4).
  def broadcast_ocr_ready(report)
    report.broadcast_replace_to(
      [ report.user, :report_editor ],
      target: "report_body_field",
      partial: "reports/body_field",
      locals: { report: report }
    )
  end
end
