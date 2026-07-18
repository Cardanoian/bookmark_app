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
    broadcast_ocr_failed(report)
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

  # OCR 실패 → compose 화면의 "읽는 중" 상태 영역(#ocr_reading_status)을 안내+재시도 링크로
  # 교체해 무한 "읽는 중" 고착을 막는다(M2). 방송 자체의 실패는 흡수해 이미 커밋된
  # :failed 상태를 보존한다. 마크업은 edit 뷰의 failed 분기와 동일하게 맞춘다.
  def broadcast_ocr_failed(report)
    return unless report

    report.broadcast_replace_to(
      [ report.user, :report_editor ],
      target: "ocr_reading_status",
      html: ocr_failed_status_html
    )
  rescue StandardError => e
    Rails.logger.error("OcrJob failure broadcast failed for report #{report&.id}: #{e.class}: #{e.message}")
  end

  def ocr_failed_status_html
    retry_path = Rails.application.routes.url_helpers.new_report_path(input_mode: :ocr)
    <<~HTML.html_safe
      <div id="ocr_reading_status" aria-live="polite" class="mb-4">
        <div class="state-banner state-banner--error">
          <span aria-hidden="true">⚠️</span>
          <span>
            사진을 못 읽었어요. 직접 입력하거나 다시 찍어 주세요.
            <a href="#{retry_path}" class="underline font-semibold">다시 찍기</a>
          </span>
        </div>
      </div>
    HTML
  end
end
