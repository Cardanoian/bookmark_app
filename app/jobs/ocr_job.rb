# 사진 업로드 → 비동기 손글씨 OCR → report.body 초안. 키 없으면 Unavailable, API 호출
# 실패·빈 응답이면 ClaudeClient::ApiError → 어느 쪽이든 :failed 로 전이시켜 pending 에
# 영구히 묶이지 않게 한다. (§9.3, P3.4)
#
# 다른 AI 잡과 같은 Claude 키를 보되 모델만 OCR 전용(`Ai::OcrService::MODEL`)이다.
class OcrJob < ApplicationJob
  queue_as :default

  # 업로드 시점의 본문 지문. 판독이 끝나 저장하기 **직전**에 다시 재어 그사이 본문이 바뀌었는지 본다
  # (2026-09-16). 판독은 몇 초에서 몇십 초가 걸리는데, 그동안 아이는 같은 글을 직접 고쳐 쓰고 제출까지
  # 할 수 있다 — 예전에는 늦게 끝난 판독이 그 글을 조건 없이 덮어, 낸 글이 판독 원문으로 되돌아가고
  # 교사·AI 가 보는 본문이 아이가 낸 것과 달라졌다.
  def self.body_digest(report)
    Digest::SHA256.hexdigest(report.body.to_s)
  end

  # AI 동의 재확인용 클라이언트 팩토리(테스트 seam, GenerateGameContentJob 선례). 잡 실행 시점에
  # 동의를 재평가해 "동의 후 사진 업로드 → 교사 철회 → 인플라이트 잡 실행" 레이스에서 미동의 학생의
  # 손글씨 이미지가 외부 AI 로 전송되지 않게 한다(P1-1). 테스트는 configured? 스텁을 주입해 무키가
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

  # body_digest: 업로드 요청이 잰 본문 지문(OcrController 가 넘긴다). 예전 판본이 큐에 남긴 잡은
  # 이 인자가 없으므로(nil) 본문 비교를 건너뛴다 — 배포 중 인플라이트 잡이 깨지지 않게.
  def perform(report, body_digest: nil)
    @body_digest = body_digest
    return discard(report, :already_submitted) if report.submitted_at.present?
    return discard(report, :body_changed) if body_changed?(report)

    unless Ai::ConsentGate.llm_allowed?(report.user, client: self.class.gate_client_factory.call)
      report.update(ai_status: :failed)
      return broadcast_ocr_failed(report)
    end

    text = Ai::OcrService.new.call(report.photo.blob)

    # 판독하는 동안 글이 제출됐거나 아이가 직접 고쳐 썼으면 덮지 않는다. 사진을 올릴 때 한 번 본 것을
    # 저장 직전에 다시 보는 이유는, 오래 걸리는 것이 바로 이 사이의 API 호출이기 때문이다.
    report.reload
    return discard(report, :already_submitted) if report.submitted_at.present?
    return discard(report, :body_changed) if body_changed?(report)

    report.update!(body: text, ai_status: :done)
    broadcast_ocr_ready(report)
  rescue Ai::OcrService::Unavailable, Ai::ClaudeClient::ApiError => e
    Rails.logger.error("OcrJob failed for report #{report&.id}: #{e.class}: #{e.message}")
    # 이미 낸 글은 실패로도 건드리지 않는다 — ai_status 는 그 글의 첨삭 상태를 가리키고 있다.
    return if report.nil? || report.reload.submitted_at.present?

    report.update(ai_status: :failed)
    broadcast_ocr_failed(report)
  end

  private

  def body_changed?(report)
    @body_digest.present? && self.class.body_digest(report) != @body_digest
  end

  # 늦게 끝난 판독을 버린다(본문·점수를 바꾸지 않는다, 2026-09-16).
  # · already_submitted — 이미 낸 글이다. **아무것도 쓰지 않는다**: ai_status 는 그 글의 첨삭 상태를
  #   가리키고 있어 여기서 done/failed 를 찍으면 첨삭 진행이 뒤바뀐 것처럼 보인다.
  # · body_changed — 아직 초안이지만 아이가 직접 쓴 글이 있다. 그 글을 살리고, 화면이 "읽는 중"에
  #   묶이지 않게 상태만 done 으로 닫은 뒤 무슨 일이 있었는지 알린다.
  def discard(report, reason)
    Rails.logger.info("OcrJob discarded stale result for report #{report&.id}: #{reason}")
    return if reason == :already_submitted

    report.update(ai_status: :done)
    broadcast_ocr_kept(report)
  end

  # OCR 초안 → 그 글의 편집 화면 본문을 교체한다(사진→텍스트 실시간, P3.4).
  # 채널은 **글 단위**([report, :report_editor], reports/edit 가 구독)다. 예전의 사용자 단위 채널은
  # 같은 학생이 다른 탭에 열어 둔 다른 초안의 본문까지 이 판독 결과로 바꿨고, 자동 저장이 켜진 뒤로는
  # 다음 입력 때 그 엉뚱한 본문이 그 초안에 조용히 저장됐다(2026-09-13 리뷰 #9).
  # 본문만 바꾸면 compose 화면의 "읽고 있어요" 배너가 그대로 남아, 글자가 채워졌는데도 화면은
  # 계속 처리 중이라고 말한다 — 학생이 제출하기를 누를 이유를 못 느끼고 떠나면 초안인 채로
  # 남는다(첨삭이 영영 안 붙던 결함의 시작점). 그래서 상태 영역도 함께 교체해 남은 행동을
  # 명시한다. 마크업은 edit 뷰의 done 분기와 동일하게 맞춘다.
  def broadcast_ocr_ready(report)
    report.broadcast_replace_to(
      [ report, :report_editor ],
      target: "report_body_field",
      partial: "reports/body_field",
      locals: { report: report }
    )
    report.broadcast_replace_to(
      [ report, :report_editor ],
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
      [ report, :report_editor ],
      target: "ocr_reading_status",
      html: ocr_failed_status_html
    )
  rescue StandardError => e
    Rails.logger.error("OcrJob failure broadcast failed for report #{report&.id}: #{e.class}: #{e.message}")
  end

  # 판독 결과를 버렸을 때의 상태 영역. 아이가 직접 쓴 글은 그대로 두었다는 것과, 사진으로 다시
  # 쓰려면 새로 찍어야 한다는 것을 함께 알린다.
  def broadcast_ocr_kept(report)
    return unless report

    report.broadcast_replace_to(
      [ report, :report_editor ],
      target: "ocr_reading_status",
      html: ocr_kept_status_html
    )
  rescue StandardError => e
    Rails.logger.error("OcrJob kept broadcast failed for report #{report&.id}: #{e.class}: #{e.message}")
  end

  def ocr_kept_status_html
    retry_path = Rails.application.routes.url_helpers.new_report_path(input_mode: :ocr)
    <<~HTML.html_safe
      <div id="ocr_reading_status" aria-live="polite" class="mb-4">
        <div class="state-banner state-banner--warning">
          #{ApplicationController.helpers.ui_icon(:warning)}
          <span>
            사진을 다 읽었지만, 그사이 직접 쓴 글이 있어 <strong>쓰던 글을 그대로 두었어요.</strong>
            사진 글로 쓰려면 <a href="#{retry_path}" class="underline font-semibold">다시 찍기</a>.
          </span>
        </div>
      </div>
    HTML
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
