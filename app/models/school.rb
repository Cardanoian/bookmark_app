class School < ApplicationRecord
  DATA_SOURCES = %w[manual sample neis].freeze
  LEGACY_SAMPLE_CODES = %w[
    7010001 7020001 7030001 7040001 7050001 7060001
    7070001 7080001 7090001 7100001 7110001 7120001
    7130001 7140001 7150001 7160001 7170001
  ].freeze

  has_many :classrooms, dependent: :destroy
  has_many :users, dependent: :nullify

  validates :name, presence: true
  validates :neis_code, uniqueness: true, allow_nil: true
  validates :data_source, inclusion: { in: DATA_SOURCES }

  scope :active, -> { where(active: true) }

  # 가입/로그인 학교 피커 1단계(시도) 옵션 — 빈 값 제외·정렬된 distinct 교육청명.
  def self.form_regions
    active.where.not(region: [ nil, "" ]).distinct.order(:region).pluck(:region)
  end
end
