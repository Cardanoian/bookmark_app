# 포인트 적립 + 후크. 적립 시 뱃지 갱신·진화 조건 검사를 연쇄 트리거한다(§13.2/§13.5).
module Pointable
  extend ActiveSupport::Concern

  # n 포인트 적립 → 저장 → 뱃지 갱신 + 진화 조건 검사. 0/음수 no-op. 최종 포인트 반환.
  # 원자 증가(update_counters)로 동시 적립의 lost update 를 막고, reload 로 최신값을 읽어
  # 후크(뱃지·진화·랭킹)가 정확한 포인트를 본다. award_points 는 트랜잭션 밖 호출이라 여기서 reload·후크가 정상.
  def award_points(amount, reason: nil)
    amount = amount.to_i
    return points if amount <= 0

    self.class.update_counters(id, points: amount)
    reload
    Rails.logger.debug { "award_points(#{amount}) user=#{id} reason=#{reason.inspect}" } if reason
    refresh_badges!
    check_evolution!
    broadcast_ranking_change
    points
  end

  # n 포인트 차감(상점 소비 등 포인트 sink)의 순수 원자 프리미티브. 잔액 부족/0 이하면 false, 성공 시 true.
  # 잔액이 충분한 경우에만 단일 조건부 UPDATE 로 차감해 double-spend/음수 잔액을 막는다.
  # reload·방송을 하지 않는다 — 트랜잭션 안에서 롤백돼도 인메모리·방송이 오염되지 않도록, 커밋 후 reload/방송은 호출자 책임(§0.3).
  def spend_points!(amount)
    amount = amount.to_i
    return false if amount <= 0

    affected = self.class.where(id: id).where("points >= ?", amount)
                   .update_all("points = points - #{amount}")
    affected.positive?
  end

  # 조건 없는 원자 적립 프리미티브(트랜잭션 안전). spend_points! 의 대칭.
  # award_points 가 쓰는 update_counters(콜백·reload·방송 없는 원자 증가)를 재사용해 lost update 를
  # 막되, reload·후크·방송은 하지 않는다 — 미션 Rewarder 가 claim(조건부 UPDATE)+credit 를 한
  # 트랜잭션으로 감싸 이중지급·under-award 를 동시에 막고, 방송·후크는 커밋 후 run_point_side_effects!
  # 로 실행하기 위함(menu_refactor 심화 §2.A.1). 0/음수 no-op.
  def credit_points!(amount)
    amount = amount.to_i
    return false if amount <= 0

    self.class.update_counters(id, points: amount)
    true
  end

  # 포인트 변동의 커밋 후 사이드이펙트(뱃지·진화·랭킹 방송). 트랜잭션 밖에서만 호출한다.
  # credit_points! 처럼 트랜잭션 안에서 원자 적립한 뒤, 커밋 후 이 메서드로 후크를 실행한다.
  def run_point_side_effects!
    reload
    refresh_badges!
    check_evolution!
    broadcast_ranking_change
  end

  # 포인트 변동 시 학급 랭킹 행을 실시간 갱신(§10). 구독자 없어도 안전한 단일 행 replace.
  # spend_points! 는 방송하지 않으므로 구매 등 트랜잭션 경로에서는 호출자가 커밋 후 직접 호출한다(§0.3).
  def broadcast_ranking_change
    return unless respond_to?(:classroom_id) && classroom_id && respond_to?(:student?) && student?

    broadcast_replace_to(
      [ classroom, :ranking ],
      target: ActionView::RecordIdentifier.dom_id(self, :ranking),
      partial: "rankings/ranking_row",
      locals: { user: self, rank: nil }
    )
  end
end
