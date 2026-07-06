# 포인트 적립 + 후크. 적립 시 뱃지 갱신·진화 조건 검사를 연쇄 트리거한다(§13.2/§13.5).
module Pointable
  extend ActiveSupport::Concern

  # n 포인트 적립 → 저장 → 뱃지 갱신 + 진화 조건 검사. 0/음수 no-op. 최종 포인트 반환.
  def award_points(amount, reason: nil)
    amount = amount.to_i
    return points if amount <= 0

    increment(:points, amount)
    save!
    Rails.logger.debug { "award_points(#{amount}) user=#{id} reason=#{reason.inspect}" } if reason
    refresh_badges!
    check_evolution!
    broadcast_ranking_change
    points
  end

  # n 포인트 차감(상점 소비 등 포인트 sink). 잔액 부족/0 이하면 false. 성공 시 true.
  def spend_points!(amount)
    amount = amount.to_i
    return false if amount <= 0 || points.to_i < amount

    update!(points: points - amount)
    broadcast_ranking_change
    true
  end

  private

  # 포인트 변동 시 학급 랭킹 행을 실시간 갱신(§10). 구독자 없어도 안전한 단일 행 replace.
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
