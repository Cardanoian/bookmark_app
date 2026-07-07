# 상점 구매(P4.8, 포인트 sink). 소모품은 수량 증가, 영구 아이템은 중복 거부.
class PurchasesController < ApplicationController
  def create
    authorize Purchase
    @item = ShopItem.find(params[:shop_item_id])
    result = buy(@item)

    @ok = result[:ok]
    @message = result[:message]
    @purchase = current_user.purchases.find_by(shop_item: @item)
    @balance = current_user.reload.points

    respond_to do |format|
      format.turbo_stream { render :create, status: @ok ? :ok : :unprocessable_entity }
      format.html do
        redirect_to shop_path, (@ok ? { notice: @message } : { alert: @message })
      end
    end
  end

  private

  # 잔액 확인 → 포인트 차감 + 구매 반영을 한 트랜잭션으로 처리.
  # spend_points! 는 원자 차감 + 불리언만 담당(방송·reload 없음). 커밋 성공 시에만 잔액을 다시 읽어 랭킹을 방송한다.
  def buy(item)
    return { ok: false, message: "포인트가 부족해요. 독후감을 더 써 볼까요?" } if current_user.points < item.cost

    if item.consumable?
      purchase = current_user.purchases.find_or_initialize_by(shop_item: item)
      purchase.quantity = purchase.new_record? ? 1 : purchase.quantity + 1
      purchase.bought_at = Time.current
    else
      return { ok: false, message: "이미 보유한 아이템이에요." } if current_user.purchases.exists?(shop_item: item)

      purchase = current_user.purchases.build(shop_item: item, quantity: 1, bought_at: Time.current)
    end

    ok = false
    current_user.transaction do
      # 원자 차감이 성공(잔액 충분)한 경우에만 구매를 확정한다. 실패 시 롤백해 무료 아이템을 막는다.
      if current_user.spend_points!(item.cost)
        purchase.save!
        ok = true
      else
        raise ActiveRecord::Rollback
      end
    end
    return { ok: false, message: "포인트가 부족해요. 독후감을 더 써 볼까요?" } unless ok

    # 커밋 후 최신 잔액을 읽어 랭킹 방송(spend_points! 는 방송하지 않는다).
    current_user.reload.broadcast_ranking_change
    { ok: true, message: "#{item.name}(을)를 구매했어요! 🎉" }
  end
end
