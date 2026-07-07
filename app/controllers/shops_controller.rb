# 케어/진화 상점(P4.8). 카테고리별 아이템 목록 + 포인트 잔액 + 보유 인벤토리.
class ShopsController < ApplicationController
  # 로그인 사용자 본인의 잔액·인벤토리·상점 카탈로그만 보여주는 표현용 화면 —
  # 교차 리소스 접근이 없어 별도 인가 대상이 없다(ShopPolicy 부재).
  skip_after_action :verify_authorized

  def show
    @items_by_category = ShopItem.order(:cost).group_by(&:category)
    @balance = current_user.points
    @inventory = current_user.purchases.index_by(&:shop_item_id)
  end
end
