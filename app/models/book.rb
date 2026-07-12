class Book < ApplicationRecord
  # 학년밴드 표준 라벨(게임 밴드 g12/g34/g56 과 정합). grade_band 는 표시·필터 전용이며
  # 게임 밴드(학생 학년에서 ReadingDomain.game_band_for 로 파생)와는 무관하다(계획 §3.1).
  GRADE_BANDS = [ "초등 1~2", "초등 3~4", "초등 5~6" ].freeze

  has_many :reports, dependent: :nullify

  enum :category, { recommended: 0, classic: 1, searched: 2 }, default: :recommended

  validates :title, presence: true
end
