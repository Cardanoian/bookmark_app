# 메일 발송 잡(ActionMailer `deliver_later` 의 실행체). 기본 `ActionMailer::MailDeliveryJob` 을
# 대체해 **발송 실패를 감사 원장에 남긴다**(ApplicationMailer 가 `delivery_job` 으로 지정).
#
# 왜 필요한가: 비밀번호 재설정은 계정 열거를 막으려고 **존재하지 않는 이메일에도 성공 화면을
# 보여준다**. 그래서 발송이 실패해도 사용자에게는 성공처럼 보이고, 로그가 없으면 "메일이 안 오는데
# 앱 어디에도 흔적이 없는" 진단 불가 상태가 된다. 실패의 유일한 관측 지점이 여기다.
#
# 실패는 **삼킨다**(재던지지 않는다). 메일 실패로 잡 큐에 실패 더미가 쌓여도 복구되는 것이 없고,
# 사용자 응답은 이미 반환된 뒤다. 다만 쿼터 초과(429)만은 시간이 지나면 풀리므로 재시도한다.
class MailDeliveryJob < ActionMailer::MailDeliveryJob
  # 무료 티어 일 100통 / 초당 10요청. 신학기처럼 순간 몰릴 때 재시도로 흡수한다.
  retry_on Resend::Error::RateLimitExceededError, wait: :polynomially_longer, attempts: 5

  rescue_from StandardError do |error|
    record_delivery_failure(error)
  end

  private

  def record_delivery_failure(error)
    classification = Mail::ResendGateway.classify(error)

    AuditLogger.record!(
      actor: nil,
      action: classification == :domain_unverified ? "mail.domain_unverified" : "mail.delivery_failed",
      target: delivery_target,
      metadata: {
        mailer: arguments[0],
        mailer_action: arguments[1],
        classification: classification,
        # 원문 메시지를 항상 보존한다 — `ResendGateway::UNVERIFIED_DOMAIN_HINT` 문자열 매칭은
        # 젬 업데이트로 깨질 수 있으므로, 분류가 틀려도 여기를 보면 원인을 알 수 있다.
        error_class: error.class.name,
        error_message: error.message.to_s.truncate(500)
      }
    )
    Rails.logger.error("[mail] delivery failed (#{classification}): #{error.class} #{error.message}")
  end

  # 수신자 이메일은 metadata 에 넣지 않고 User 를 target 으로 건다(감사 원장은 이미 target_id 로
  # 대상을 식별하므로 주소를 중복 저장할 이유가 없다).
  def delivery_target
    arguments.last.try(:[], :args)&.find { |argument| argument.is_a?(User) }
  end
end
