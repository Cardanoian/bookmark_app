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

  # 활성 몬스터를 다음 폼으로 진화(제자리). 진화 뱃지 갱신 후 새 폼 반환(불가 시 nil).
  def evolve_active_monster!
    monster = active_monster
    return nil unless monster&.evolvable?

    form = monster.evolve!
    refresh_badges!
    form
  end
end
