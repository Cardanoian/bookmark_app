# 학생 보유/발견 몬스터 = 도감 수집 상태. 라인당 1행(제자리 진화 — monster_species_id 갱신).
class UserMonster < ApplicationRecord
  belongs_to :user
  belongs_to :monster_species

  validates :dex_no, uniqueness: { scope: :user_id }

  before_validation :set_dex_no_from_species, on: :create

  # 현재 폼(종). 가독성 별칭.
  def species
    monster_species
  end

  # 다음 진화 폼. 완전형이면 nil.
  def next_form
    monster_species&.next_form
  end

  # 진화 가능? 다음 폼이 있고, 현재 폼의 evolve_condition 을 모두 충족.
  def evolvable?
    return false if monster_species&.evolve_condition.blank?
    return false unless next_form

    ReadingStats.new(user).meets?(monster_species.evolve_condition)
  end

  # 제자리 진화 실행(monster_species 교체 + evolved_at). 새 폼 반환(없으면 nil).
  def evolve!
    form = next_form
    return nil unless form

    update!(monster_species: form, evolved_at: Time.current)
    form
  end

  private

  def set_dex_no_from_species
    self.dex_no ||= monster_species&.dex_no
  end
end
