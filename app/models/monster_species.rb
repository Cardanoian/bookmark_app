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
  validate :evolve_condition_must_be_valid_json
  validate :evolves_from_must_not_be_self
  validate :stage_after_evolves_from

  # 진화 규칙(evolve_condition JSON)을 텍스트에어리어에서 안전하게 편집하기 위한
  # 가상 속성. 잘못된 JSON 은 크래시 대신 검증 오류로 처리한다(P7.3).
  attr_writer :evolve_condition_json

  # 다음 단계 폼(진화 대상). 없으면 nil(완전형).
  def next_form
    next_forms.order(:stage).first
  end

  # 폼에 표시할 evolve_condition 의 JSON 문자열. 편집 중 값이 있으면 그것을 우선한다.
  def evolve_condition_json
    return @evolve_condition_json if defined?(@evolve_condition_json) && @evolve_condition_json

    evolve_condition.present? ? JSON.pretty_generate(evolve_condition) : ""
  end

  private

  # evolve_condition_json 이 주어졌으면 파싱해 evolve_condition 에 반영한다.
  # 파싱 실패 시 플래그를 세워 검증에서 오류로 변환한다(크래시 방지).
  def evolve_condition_must_be_valid_json
    return unless defined?(@evolve_condition_json) && @evolve_condition_json

    raw = @evolve_condition_json.to_s.strip
    if raw.blank?
      self.evolve_condition = nil
      return
    end

    self.evolve_condition = JSON.parse(raw)
  rescue JSON::ParserError
    errors.add(:evolve_condition, "은(는) 올바른 JSON 형식이어야 합니다")
  end

  # 진화체인 무결성: 자기 자신으로 진화할 수 없다.
  def evolves_from_must_not_be_self
    return if evolves_from_id.blank? || id.blank?

    errors.add(:evolves_from_id, "자기 자신으로 진화할 수 없습니다") if evolves_from_id == id
  end

  # 진화체인 무결성: 진화 이후 단계는 이전 단계보다 높아야 한다.
  def stage_after_evolves_from
    return if evolves_from.blank? || stage.blank? || evolves_from.stage.blank?

    errors.add(:stage, "은(는) 진화 이전 단계보다 높아야 합니다") if stage <= evolves_from.stage
  end
end
