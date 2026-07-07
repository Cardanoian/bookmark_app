# 뱃지 획득 트리거(User). 충족 조건 뱃지를 멱등하게 부여(§13.3, monsters.md §6.3).
module Badgeable
  extend ActiveSupport::Concern

  # 현재 충족되는 모든 뱃지 부여(중복 없음).
  def refresh_badges!
    stats = ReadingStats.new(self)
    Badge::KEYS.each do |key|
      grant_badge(key) if badge_condition_met?(key, stats)
    end
  end

  private

  # dex_half/dex_complete 분모는 24 설계 라인 고정(시드된 12가 아님 — 조기 발부 방지).
  def badge_condition_met?(key, stats)
    case key
    when "first" then stats.reports >= 1
    when "three" then stats.reports >= 3
    when "ten" then stats.reports >= 10
    when "levelA" then stats.a_grades >= 1
    when "tripleA" then stats.a_grades >= 3
    when "reviser" then stats.revisions >= 1
    # grower(성장의 증거)는 reviser(고쳐쓰기 1회)보다 강한 이정표 — 향상된 고쳐쓰기 3회 이상.
    # (monsters.md §6.3 은 grower 임계값을 명시하지 않아, 두 뱃지가 항상 동시 해제되지 않도록
    #  reviser=1 과 구분되는 상위 임계값을 둔다.)
    when "grower" then stats.revisions >= 3
    when "challenger" then stats.challenges >= 1
    when "ocr" then reports.ocr.exists?
    when "first_evolve" then user_monsters.where.not(evolved_at: nil).exists?
    when "dex_half" then stats.dex_count >= 12
    when "dex_complete" then stats.dex_count >= MonsterSpecies::DESIGN_LINE_COUNT
    when "final_form"
      user_monsters.joins(:monster_species)
                   .where(monster_species: { stage: MonsterSpecies::MAX_STAGE }).exists?
    else false
    end
  end

  def grant_badge(key)
    badge = Badge.find_by(key: key)
    return unless badge

    user_badges.find_or_create_by!(badge: badge) do |user_badge|
      user_badge.earned_at = Time.current
    end
  end
end
