# 가입 인증 메일 발송의 단일 진입점. 가입(RegistrationsController)과 재발송
# (EmailVerificationsController) 두 호출부가 토큰 발급 규약을 공유하도록 한 곳에 모은다.
#
# **발송 조건을 여기서 fail-closed 로 판정한다** — 이메일이 없거나 이미 인증된 계정에는 보내지
# 않는다. 호출부가 판정을 빠뜨려도 중복·무의미 발송이 새어 나가지 않는다(무료 티어 일 100통).
module EmailVerifications
  module_function

  # 보냈으면 true, 조건 미달로 보내지 않았으면 false.
  def deliver(user)
    return false unless deliverable?(user)

    AccountMailer.email_verification(user, user.generate_token_for(:email_verification)).deliver_later
    true
  end

  def deliverable?(user)
    user.present? && user.staff? && user.email.present? && !user.email_verified?
  end
end
