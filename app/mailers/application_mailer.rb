# 앱 메일러 공통 기반. 발신 주소는 Resend 에서 검증 완료된 도메인(chaekgalpi.net)의 주소를 쓴다 —
# 미검증 도메인으로는 계정 소유자 본인에게만 발송되고 그 외에는 403 이 나므로, 발신 주소는
# `Mail::ResendGateway` 한 곳에서만 결정한다(ENV `MAIL_FROM` 로 오버라이드 가능).
class ApplicationMailer < ActionMailer::Base
  default from: -> { Mail::ResendGateway.from_address }
  layout "mailer"

  # `deliver_later` 실행체를 교체해 발송 실패를 감사 원장에 남긴다(MailDeliveryJob 주석 참조).
  self.delivery_job = MailDeliveryJob
end
