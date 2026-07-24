# 로그인 브루트포스 방어(fail2ban + 정답-우선)의 재사용 concern. SessionsController 에서 추출해
# AccountLinksController(계정 연동 인증)와 공유한다. 두 축으로 방어한다:
#   ① IP 실패(IP_THROTTLE, 3분 10회) ② 계정 실패(ACCOUNT_THROTTLE, 10분 8회).
#
# **먼저 인증**하고, 정답이면 항상 통과시키며 두 축 실패 카운터를 리셋한다(저엔트로피 파라미터로
# 피해자 계정을 잠그는 DoS·NAT 오탐 무력화). **오답만** 세고, 오답이 한도를 넘으면 추가 추측을 막는다.
#
# **축 키는 포함 컨트롤러가 넘긴다**(parameterize). 이로써 로그인과 계정 연동이:
#   - **계정 축을 공유**(같은 `login:account:...` 네임스페이스 — 한 계정에 대한 자격증명 브루트포스
#     표면을 로그인·연동 양쪽에서 합산한다)하고,
#   - **IP 축을 분리**(로그인 `login:ip:...` vs 연동 `linkauth:ip:...` — NAT 뒤 로그인 가용성이
#     연동 시도로 오염되지 않게 한다)한다.
#
# rate_limit_store 는 각 포함 컨트롤러가 **독립 클래스 접근자**로 갖는다(class_attribute) — 테스트가
# `SessionsController.rate_limit_store` / `AccountLinksController.rate_limit_store` 를 따로 주입한다.
# 프로덕션은 nil → Rails.cache(Solid Cache 원자 increment). test 기본 캐시는 :null_store 라 무카운팅.
module LoginThrottling
  extend ActiveSupport::Concern

  IP_THROTTLE = { limit: 10, period: 3.minutes }.freeze
  ACCOUNT_THROTTLE = { limit: 8, period: 10.minutes }.freeze

  included do
    class_attribute :rate_limit_store, instance_accessor: false
  end

  private

  # IP·계정 두 축 중 하나라도 **실패 누적**이 한도 이상이면 true. peek 는 증가 없이 조회만 한다.
  def locked_out?(ip_key:, account_key:)
    limiter = login_limiter
    limiter.peek(ip_key) >= IP_THROTTLE[:limit] ||
      limiter.peek(account_key) >= ACCOUNT_THROTTLE[:limit]
  end

  # 로그인 실패 1회 기록(IP·계정 두 축 원자 increment).
  def register_login_failure(ip_key:, account_key:)
    limiter = login_limiter
    limiter.record_failure(ip_key, IP_THROTTLE[:period])
    limiter.record_failure(account_key, ACCOUNT_THROTTLE[:period])
  end

  # 인증 성공 시 IP·계정 실패 카운터를 모두 리셋한다(정답 로그인은 누적 실패를 해제).
  def reset_login_failures(ip_key:, account_key:)
    limiter = login_limiter
    limiter.reset(ip_key)
    limiter.reset(account_key)
  end

  def login_limiter
    @login_limiter ||= RateLimiter.new(store: self.class.rate_limit_store || Rails.cache)
  end
end
