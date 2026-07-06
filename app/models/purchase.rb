# 상점 구매 기록. 소모품은 수량 증가, 영구 장식은 unique(user_id, shop_item_id).
class Purchase < ApplicationRecord
  belongs_to :user
  belongs_to :shop_item
end
