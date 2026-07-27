# 메일 발송 요청의 남용 방어(비밀번호 재설정 요청 · 인증 메일 재발송).
#
# `LoginThrottling` 과 같은 프리미티브(`RateLimiter` = Solid Cache 원자 increment)를 쓰지만
# **성격이 다르다**. 로그인 스로틀은 "오답만 세는 fail2ban"이라 정답이면 카운터를 리셋하지만,
# 여기서는 **정상 요청 자체가 비용**이다(메일 1통 = Resend 무료 티어 일 100통 소진). 그래서
# 성공·실패를 가리지 않고 모든 시도를 세고, 리셋 개념이 없다.
#
# 두 축으로 막는다:
#   ① IP 축 — 한 곳에서 여러 주소로 메일 폭탄을 쏘는 것을 막는다.
#   ② 계정/이메일 축 — 특정인의 메일함을 도배하는 것(메일 폭탄 괴롭힘)을 막는다.
# 축 키는 **포함 컨트롤러가 만들어 넘긴다**(LoginThrottling 과 동일한 parameterize 규약).
#
# `rate_limit_store` 는 포함 컨트롤러마다 독립 class_attribute 로 생기므로, 테스트가
# `PasswordResetsController.rate_limit_store` 를 개별 주입할 수 있다. 프로덕션은 nil → Rails.cache
# (Solid Cache). test 기본 캐시는 :null_store 라 주입하지 않으면 카운팅되지 않는다(= 무제한 허용).
module MailRateLimiting
  extend ActiveSupport::Concern

  # 값 근거: 정상 사용자는 시간당 1~2회면 충분하다(오타 정정·스팸함 확인 후 재시도). IP 축을
  # 계정 축보다 넉넉히 둔 것은 학교 단일 공인 IP(NAT) 뒤에서 여러 교사가 동시에 요청할 수
  # 있기 때문이다.
  IP_THROTTLE = { limit: 10, period: 1.hour }.freeze
  ACCOUNT_THROTTLE = { limit: 3, period: 1.hour }.freeze

  included do
    class_attribute :rate_limit_store, instance_accessor: false
  end

  private

  # 두 축 모두 한도 이내면 true(그리고 두 카운터를 증가시킨다). && 단락 평가로 IP 축에서
  # 막히면 계정 카운터는 올리지 않는다 — 남의 IP 가 막혔다고 내 계정 한도가 깎이지 않게.
  def mail_request_allowed?(ip_key:, account_key:)
    limiter = mail_limiter
    limiter.allow?(ip_key, **IP_THROTTLE) &&
      limiter.allow?(account_key, **ACCOUNT_THROTTLE)
  end

  def mail_limiter
    @mail_limiter ||= RateLimiter.new(store: self.class.rate_limit_store || Rails.cache)
  end
end
