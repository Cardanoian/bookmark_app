# 케어/진화 상점(P4.8). 카테고리별 아이템 목록 + 포인트 잔액 + 보유 인벤토리.
class ShopsController < ApplicationController
  def show
    @items_by_category = ShopItem.order(:cost).group_by(&:category)
    @balance = current_user.points
    @inventory = current_user.purchases.index_by(&:shop_item_id)
  end
end
