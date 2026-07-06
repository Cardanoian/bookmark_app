# 반려 몬스터 도감 카탈로그(시드). 진화 라인(dex_no) × 3단계(stage) 폼.
class MonsterSpecies < ApplicationRecord
  MAX_STAGE = 3
  # 도감 완성도·dex 뱃지 분모(설계 라인 수 — 시드된 12가 아니라 24 고정, monsters.md §6.3).
  DESIGN_LINE_COUNT = 24

  enum :element, { story: 0, knowledge: 1, emotion: 2, adventure: 3, nature: 4, imagination: 5 }
  enum :rarity, { common: 0, rare: 1, epic: 2 }

  belongs_to :evolves_from, class_name: "MonsterSpecies", optional: true
  has_many :next_forms, class_name: "MonsterSpecies", foreign_key: :evolves_from_id,
                        inverse_of: :evolves_from, dependent: :nullify
  has_many :user_monsters, dependent: :destroy

  validates :key, presence: true, uniqueness: true

  # 다음 단계 폼(진화 대상). 없으면 nil(완전형).
  def next_form
    next_forms.order(:stage).first
  end
end
