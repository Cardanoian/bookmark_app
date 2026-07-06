# 케어/진화 아이템 상점 카탈로그(포인트 sink). 아바타 상점에서 몬스터 케어로 피벗.
class ShopItem < ApplicationRecord
  enum :category, { food: 0, evolution_stone: 1, care: 2, decoration: 3, accessory: 4 }

  has_many :purchases, dependent: :destroy

  validates :name, presence: true
end
