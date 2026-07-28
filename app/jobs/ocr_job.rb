# 사진 업로드 → 비동기 손글씨 OCR → report.body 초안. 키 없으면 Unavailable, API 호출
# 실패·빈 응답이면 ClaudeClient::ApiError → 어느 쪽이든 :failed 로 전이시켜 pending 에
# 영구히 묶이지 않게 한다. (§9.3, P3.4)
class OcrJob < ApplicationJob
  queue_as :default

  # AI 동의 재확인용 클라이언트 팩토리(테스트 seam, GenerateGameContentJob 선례). 잡 실행 시점에
  # 동의를 재평가해 "동의 후 사진 업로드 → 교사 철회 → 인플라이트 잡 실행" 레이스에서 미동의 학생의
  # 손글씨 이미지가 Claude 로 전송되지 않게 한다(P1-1). 테스트는 configured? 스텁을 주입해 무키가
  # 아닌 미동의 사유로 차단됨을 검증한다.
  class << self
    attr_writer :gate_client_factory

    def gate_client_factory
      @gate_client_factory ||= -> { Ai::ClaudeClient.new }
    end

    def reset_factories!
      @gate_client_factory = nil
    end
  end

  def perform(report)
    unless Ai::ConsentGate.llm_allowed?(report.user, client: self.class.gate_client_factory.call)
      report.update(ai_status: :failed)
      return broadcast_ocr_failed(report)
    end

    text = Ai::OcrService.new.call(report.photo.blob)
    report.update!(body: text, ai_status: :done)
    broadcast_ocr_ready(report)
  rescue Ai::OcrService::Unavailable, Ai::ClaudeClient::ApiError => e
    Rails.logger.error("OcrJob failed for report #{report&.id}: #{e.class}: #{e.message}")
    report&.update(ai_status: :failed)
    broadcast_ocr_failed(report)
  end

  private

  # OCR 초안 → 작성자의 에디터 본문을 교체한다(사진→텍스트 실시간, P3.4).
  # 본문만 바꾸면 compose 화면의 "읽고 있어요" 배너가 그대로 남아, 글자가 채워졌는데도 화면은
  # 계속 처리 중이라고 말한다 — 학생이 제출하기를 누를 이유를 못 느끼고 떠나면 초안인 채로
  # 남는다(첨삭이 영영 안 붙던 결함의 시작점). 그래서 상태 영역도 함께 교체해 남은 행동을
  # 명시한다. 마크업은 edit 뷰의 done 분기와 동일하게 맞춘다.
  def broadcast_ocr_ready(report)
    report.broadcast_replace_to(
      [ report.user, :report_editor ],
      target: "report_body_field",
      partial: "reports/body_field",
      locals: { report: report }
    )
    report.broadcast_replace_to(
      [ report.user, :report_editor ],
      target: "ocr_reading_status",
      html: ocr_ready_status_html
    )
  rescue StandardError => e
    # 본문 교체가 이미 성공했을 수 있으므로 방송 실패로 :done 커밋을 뒤집지 않는다
    # (broadcast_ocr_failed 의 흡수 규약과 동일). 다음 로드에서 레코드 상태로 복원된다.
    Rails.logger.error("OcrJob ready broadcast failed for report #{report&.id}: #{e.class}: #{e.message}")
  end

  def ocr_ready_status_html
    <<~HTML.html_safe
      <div id="ocr_reading_status" aria-live="polite" class="mb-4">
        <div class="state-banner state-banner--success">
          #{ApplicationController.helpers.ui_icon(:check)}
          <span>사진을 다 읽었어요. 잘못 읽은 곳을 고친 뒤 <strong>제출하기</strong>를 눌러야 선생님 첨삭이 시작돼요.</span>
        </div>
      </div>
    HTML
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
    warning_icon = ApplicationController.helpers.ui_icon(:warning)
    <<~HTML.html_safe
      <div id="ocr_reading_status" aria-live="polite" class="mb-4">
        <div class="state-banner state-banner--error">
          #{warning_icon}
          <span>
            사진을 못 읽었어요. 직접 입력하거나 다시 찍어 주세요.
            <a href="#{retry_path}" class="underline font-semibold">다시 찍기</a>
          </span>
        </div>
      </div>
    HTML
  end
end
