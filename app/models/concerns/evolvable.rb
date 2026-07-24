# 진화 엔진 후크(User). report 승인·포인트 지급·뱃지 획득 시점에 활성 몬스터 조건 평가.
module Evolvable
  extend ActiveSupport::Concern

  # 활성 몬스터가 진화 가능하면 true("진화 가능!" 배지 표시용). 부작용 없음.
  def check_evolution!
    active_monster&.evolvable? || false
  end

  # 조건 충족 + 다음 폼이 있는 보유 몬스터 목록.
  def evolvable_monsters
    user_monsters.select(&:evolvable?)
  end

  # 보유 몬스터를 다음 폼으로 진화(제자리)하며 현재 단계의 points 조건만큼 포인트를 소모한다.
  # 차감과 진화를 한 트랜잭션으로 묶어 둘 중 하나만 반영되는 상태를 막는다.
  def evolve_monster!(monster)
    form = nil
    expected_species_id = monster.monster_species_id

    transaction do
      reload
      monster.reload
      valid_request = monster.user_id == id &&
                      monster.monster_species_id == expected_species_id &&
                      monster.evolvable?
      raise ActiveRecord::Rollback unless valid_request

      cost = monster.evolution_cost
      raise ActiveRecord::Rollback unless cost.zero? || spend_points!(cost)

      form = monster.evolve!
      raise ActiveRecord::Rollback unless form

      reload
      refresh_badges!
    end

    form
  end

  # 활성 몬스터 진화도 동일한 포인트 차감 규칙을 사용한다.
  def evolve_active_monster!
    monster = active_monster
    return nil unless monster

    evolve_monster!(monster)
  end
end
