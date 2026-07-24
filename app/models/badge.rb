# 뱃지 카탈로그(13종 시드). key 로 조건 트리거(Badgeable concern).
class Badge < ApplicationRecord
  KEYS = %w[
    first three ten levelA tripleA reviser grower challenger ocr
    first_evolve dex_half dex_complete final_form
  ].freeze

  has_many :user_badges, dependent: :destroy
  has_many :users, through: :user_badges

  validates :key, presence: true, uniqueness: true
end
