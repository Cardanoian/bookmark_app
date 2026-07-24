require "test_helper"

# Phase 2b §2b.5 — Solid Cache 원자 increment 기반 rate limit / 예산 유틸.
# test 환경 기본 캐시(null_store)는 무카운팅이므로, 카운팅 가능한 MemoryStore 를 주입해 검증한다.
class RateLimiterTest < ActiveSupport::TestCase
  setup do
    @store = ActiveSupport::Cache::MemoryStore.new
    @limiter = RateLimiter.new(store: @store)
  end

  test "allow? permits up to the limit and blocks the N+1th call" do
    3.times { |i| assert @limiter.allow?("k", limit: 3, period: 1.hour), "#{i + 1}번째 허용" }
    assert_not @limiter.allow?("k", limit: 3, period: 1.hour), "4번째(N+1)는 차단"
  end

  test "separate keys have independent counters" do
    3.times { @limiter.allow?("a", limit: 3, period: 1.hour) }
    assert @limiter.allow?("b", limit: 3, period: 1.hour), "다른 키는 독립 카운터"
  end

  test "warming_allowed? blocks the same user past the per-user hourly limit" do
    limit = RateLimiter::WARMING_PER_USER[:limit]
    limit.times { assert @limiter.warming_allowed?(42) }
    assert_not @limiter.warming_allowed?(42), "per-user 한도 초과 → 워밍 차단(오프라인 강등)"
  end

  test "warming_allowed? blocks all users once the global daily budget is exhausted" do
    # 예산을 소진시키되 per-user 한도에 걸리지 않도록 유저를 번갈아 쓴다.
    budget = RateLimiter::WARMING_DAILY_BUDGET[:limit]
    budget.times { |i| assert @limiter.warming_allowed?(1000 + i) }
    assert_not @limiter.warming_allowed?(999_999), "글로벌 일일 예산 소진 → 신규 유저도 차단"
  end
end
