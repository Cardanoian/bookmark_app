class School < ApplicationRecord
  has_many :classrooms, dependent: :destroy
  has_many :users, dependent: :nullify

  validates :name, presence: true
  validates :neis_code, uniqueness: true, allow_nil: true

  # 가입/로그인 학교 피커 1단계(시도) 옵션 — 빈 값 제외·정렬된 distinct 교육청명.
  def self.form_regions
    where.not(region: [ nil, "" ]).distinct.order(:region).pluck(:region)
  end
end
