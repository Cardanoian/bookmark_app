# Solid Cache 원자 increment 기반 rate limit / 예산 유틸(Phase 2b §2b.5).
#
# 온디맨드 게임 콘텐츠 워밍(per-user rate limit + 글로벌 일일 예산)이 사용하며,
# Phase 6 이슈 #7(로그인 스로틀)도 같은 원자 increment 프리미티브를 재사용하도록 설계했다.
# 한도/예산 초과 시 워밍을 건너뛰고 오프라인으로 우아하게 강등한다(무중단 계약 유지).
#
# 저장소는 주입 가능(기본 Rails.cache = 프로덕션 Solid Cache). 테스트는 카운팅 가능한
# MemoryStore 를 주입한다(test 환경 기본 캐시는 null_store 라 무카운팅 → 무제한 허용).
class RateLimiter
  # 워밍 방어 기본값. per-user 는 시간당, 글로벌 예산은 일당.
  WARMING_PER_USER = { limit: 20, period: 1.hour }.freeze
  WARMING_DAILY_BUDGET = { limit: 500, period: 1.day }.freeze

  def initialize(store: Rails.cache, now: -> { Time.current })
    @store = store
    @now = now
  end

  # key 를 원자 증가시키고 한도(limit) 이내면 true. increment 는 항상 수행(관측·경보용 카운트 유지).
  def allow?(key, limit:, period:)
    bump(key, period) <= limit
  end

  # 증가 없이 현재 카운트만 조회한다(fail2ban 락아웃 판정용 — 시도 자체는 세지 않고 "실패"만 센다).
  # 이름을 count 로 두면 Brakeman 이 AR#count SQL 인젝션으로 오탐하므로 peek 로 둔다(캐시 read 일 뿐).
  def peek(key)
    @store.read("rate_limiter:#{key}", raw: true).to_i
  end

  # 실패 1회 기록(원자 increment). 판정 없이 카운트만 올린다(로그인 실패 등).
  def record_failure(key, period)
    bump(key, period)
  end

  # 카운터 리셋(fail2ban: 인증 성공 시 해당 계정의 누적 실패를 해제).
  def reset(key)
    @store.delete("rate_limiter:#{key}")
  end

  # 워밍 허용 여부: per-user rate limit AND 글로벌 일일 예산 둘 다 통과해야 true.
  # && 단락 평가로 per-user 가 막히면 예산 카운터는 올리지 않는다.
  def warming_allowed?(user_id)
    now = @now.call
    hour_bucket = now.strftime("%Y%m%d%H")
    day_bucket = now.strftime("%Y%m%d")

    allow?("warming:user:#{user_id}:#{hour_bucket}", **WARMING_PER_USER) &&
      allow?("warming:budget:#{day_bucket}", **WARMING_DAILY_BUDGET)
  end

  private

  # 원자 increment. 미존재 키에 increment 가 nil 을 돌려주는 스토어(초기화 필요)는 1 로 세팅한다.
  def bump(key, period)
    namespaced = "rate_limiter:#{key}"
    count = @store.increment(namespaced, 1, expires_in: period)
    return count if count

    @store.write(namespaced, 1, expires_in: period, raw: true)
    1
  end
end
