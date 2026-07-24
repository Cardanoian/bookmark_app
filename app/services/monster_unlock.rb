# 몬스터 라인 자동 해금 평가(monster_unlocks.md §4). 스타터 이후의 노력 기반 발견을 담당한다.
# 미보유·stage1·unlock_condition 존재 라인만 순회해 ReadingStats#meets?(AND 판정)를 충족하면
# MonsterAcquisition#discover_monster! 로 1단계 폼을 지급한다. 가챠·확률·유료 경로 없음.
#
# fixpoint 루프: dex_count(보유 라인 수) 를 조건으로 쓰는 라인(dex 24)은 "발견이 발견을 부르는"
# 캐스케이드다. ReadingStats#dex_count 는 인스턴스 단위로 메모이즈되므로 한 패스에서 몬스터를
# 만들어도 같은 인스턴스는 값을 갱신하지 않는다. 그래서 신규 발견이 0이 될 때까지 ReadingStats 를
# 매 라운드 새로 만들며 반복한다(최대 24라운드 = 라인 수 상한). 트리거 호출부는 evaluate! 를
# 1회만 호출하고 반복은 여기(서비스 내부)에서만 한다(승인 핫패스 지연 방지).
class MonsterUnlock
  # 캐스케이드 반복 상한(전 라인이 한 번에 다 열려도 종료 보장).
  MAX_ROUNDS = MonsterSpecies::DESIGN_LINE_COUNT

  def initialize(user)
    @user = user
    @acquisition = MonsterAcquisition.new(user)
  end

  # 조건 충족 라인을 지급하고, 이번 호출에서 새로 발견한 UserMonster 목록을 반환한다.
  def evaluate!
    candidates = unlockable_lines
    discovered = []

    MAX_ROUNDS.times do
      stats = ReadingStats.new(@user)
      owned = @user.user_monsters.pluck(:dex_no).to_set
      newly = candidates.reject { |species| owned.include?(species.dex_no) }
                        .select { |species| stats.meets?(species.unlock_condition) }
                        .filter_map { |species| discover(species) }
      break if newly.empty?

      discovered.concat(newly)
    end

    discovered
  end

  private

  # 스타터 이후 자동 해금 대상 = stage1·unlock_condition 존재 라인(dex_no 순).
  def unlockable_lines
    MonsterSpecies.where(stage: 1).where.not(unlock_condition: nil).order(:dex_no).to_a
  end

  # 개별 라인 지급. 한 라인의 실패(동시성 RecordNotUnique 등)가 전체 평가를 막지 않도록 rescue 한다.
  def discover(species)
    monster = @acquisition.discover_monster!(species.dex_no)
    Rails.logger.info("[MonsterUnlock] user=#{@user.id} discovered dex=#{species.dex_no}") if monster
    monster
  rescue StandardError => error
    Rails.logger.warn("[MonsterUnlock] user=#{@user.id} dex=#{species.dex_no} 해금 실패: #{error.class}: #{error.message}")
    nil
  end
end
