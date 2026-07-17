# 활동 확정(독후감 승인·토론 글·스타터·게임 완료) 지점에서 몬스터 해금을 재평가하고
# flash 안내 문구를 만드는 공용 헬퍼(monster_unlocks.md §4). 트리거 컨트롤러가 include 한다.
module MonsterDiscovery
  extend ActiveSupport::Concern

  private

  # user 가 학생이면 해금을 재평가하고 이번에 새로 발견한 UserMonster 목록을 반환한다(비학생은 []).
  # 몬스터 도감은 학생 전용 개념이라 교직원 작성자(예: 토론 글) 에는 지급하지 않는다.
  def evaluate_monster_unlocks(user)
    return [] unless user&.student?

    MonsterUnlock.new(user).evaluate!
  end

  # 발견 몬스터가 있으면 안내 문구를 덧붙인다(발견 연출 UI 전체는 후속 polish).
  def with_discovery(message, discovered)
    return message if discovered.blank?

    names = discovered.map { |monster| monster.species.name }.join(", ")
    "#{message} 새 몬스터를 발견했어요: #{names} 🎉"
  end
end
