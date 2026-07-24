# 학생 보유/발견 몬스터 = 도감 수집 상태. 라인당 1행(제자리 진화 — monster_species_id 갱신).
class UserMonster < ApplicationRecord
  belongs_to :user
  belongs_to :monster_species

  validates :dex_no, uniqueness: { scope: :user_id }

  # 아직 발견 연출을 보여 주지 않은(celebrated_at IS NULL) 개체. 부분 인덱스
  # index_user_monsters_pending_discovery 로 조회한다. 학생이 아무 페이지나 로드하면
  # 레이아웃이 이 스코프로 축하 모달 큐를 채우고, 연출 후 discoveries#acknowledge 가
  # celebrated_at 을 마킹해 재노출을 막는다(영속 드레인 — flash·broadcast 유실 방지).
  scope :pending_celebration, -> { where(celebrated_at: nil) }

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

  # 현재 단계에서 다음 단계로 진화할 때 소모할 포인트.
  # evolve_condition 의 points 임계값을 진화 비용의 단일 진실로 사용한다.
  def evolution_cost
    monster_species&.evolve_condition&.fetch("points", 0).to_i
  end

  # 제자리 진화 실행(monster_species 교체 + evolved_at). 새 폼 반환(없거나 이미 진화했으면 nil).
  # 현재 종을 WHERE 조건에 포함해 동시 진화 요청이 같은 단계를 두 번 확정하지 못하게 한다.
  def evolve!
    form = next_form
    return nil unless form

    evolved = self.class.where(id: id, monster_species_id: monster_species_id)
                        .update_all(monster_species_id: form.id, evolved_at: Time.current, updated_at: Time.current)
    return nil if evolved.zero?

    reload
    form
  end

  private

  def set_dex_no_from_species
    self.dex_no ||= monster_species&.dex_no
  end
end
