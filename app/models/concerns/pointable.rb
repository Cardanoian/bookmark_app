# 포인트 적립 + 후크. 적립 시 뱃지 갱신·진화 조건 검사를 연쇄 트리거한다(§13.2/§13.5).
module Pointable
  extend ActiveSupport::Concern

  included do
    before_validation :initialize_experience_from_points, on: :create
  end

  # n 포인트 적립 → 같은 양의 누적 경험치 적립 → 뱃지 갱신 + 진화 조건 검사.
  # 0/음수 no-op. 최종 포인트 반환. 포인트와 경험치를 한 UPDATE 에서 원자 증가해
  # 동시 적립의 lost update 및 둘 사이의 불일치를 막고, reload 로 최신값을 읽어
  # 후크(뱃지·진화·랭킹)가 정확한 포인트를 본다. award_points 는 트랜잭션 밖 호출이라 여기서 reload·후크가 정상.
  def award_points(amount, reason: nil)
    amount = amount.to_i
    return points if amount <= 0

    self.class.update_counters(id, points: amount, experience: amount)
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

  # 이미 지급된 보상이 재채점 등으로 정정될 때 포인트와 그 보상에서 생긴 경험치를 함께 회수한다.
  # 일반 소비는 spend_points! 를 사용하므로 경험치가 유지되고, 이 메서드는 지급 자체의 정정에만 쓴다.
  # 포인트를 이미 소비했더라도 두 값 모두 0 아래로 내려가지 않는다.
  def revoke_points!(amount)
    amount = amount.to_i
    return false if amount <= 0

    self.class.where(id: id).update_all(
      "points = MAX(points - #{amount}, 0), experience = MAX(experience - #{amount}, 0)"
    ).positive?
  end

  # 조건 없는 포인트+경험치 원자 적립 프리미티브(트랜잭션 안전). spend_points! 의 대칭.
  # award_points 가 쓰는 update_counters(콜백·reload·방송 없는 원자 증가)를 재사용해 lost update 를
  # 막되, reload·후크·방송은 하지 않는다 — 미션 Rewarder 가 claim(조건부 UPDATE)+credit 를 한
  # 트랜잭션으로 감싸 이중지급·under-award 를 동시에 막고, 방송·후크는 커밋 후 run_point_side_effects!
  # 로 실행하기 위함(menu_refactor 심화 §2.A.1). 0/음수 no-op.
  def credit_points!(amount)
    amount = amount.to_i
    return false if amount <= 0

    self.class.update_counters(id, points: amount, experience: amount)
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

  private

  # 가져오기·시드처럼 생성 시점부터 포인트를 가진 계정도 같은 양의 경험치로 시작한다.
  # 이후 모든 증감은 위의 원자 프리미티브를 거치므로 생성 시에만 보정하면 된다.
  def initialize_experience_from_points
    self.experience = points.to_i if experience.to_i.zero? && points.to_i.positive?
  end
end
