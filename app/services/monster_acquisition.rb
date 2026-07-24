# 몬스터 획득(노력 기반, 가챠 금지). 스타터 선택 + 마일스톤 발견(monsters.md §6.1).
class MonsterAcquisition
  # 스타터 선택지 3종(서로 다른 속성 — story/knowledge/nature).
  STARTERS = %w[pup_1 cat_1 hedgehog_1].freeze

  class InvalidStarter < StandardError; end
  class AlreadyOwned < StandardError; end

  def initialize(user)
    @user = user
  end

  # 스타터 1종 선택 → user_monster 생성 + 활성 몬스터 지정. 잘못/중복 선택 거부.
  def choose_starter!(key)
    key = key.to_s
    raise InvalidStarter, "invalid starter: #{key}" unless STARTERS.include?(key)

    species = MonsterSpecies.find_by!(key: key)
    raise AlreadyOwned, "already owns dex #{species.dex_no}" if owns_line?(species.dex_no)

    monster = create_monster(species)
    @user.update!(active_monster: monster)
    monster
  end

  # 마일스톤 발견(레벨업·뱃지·챌린지 등). 라인의 stage 1 폼 생성. 미보유 시에만.
  # identifier = dex_no(정수/숫자문자열) 또는 종 key. 랜덤/가챠 경로 없음.
  def discover_monster!(identifier)
    dex_no = resolve_dex_no(identifier)
    return nil unless dex_no
    return nil if owns_line?(dex_no)

    species = MonsterSpecies.find_by(dex_no: dex_no, stage: 1)
    return nil unless species

    create_monster(species)
  end

  private

  def owns_line?(dex_no)
    @user.user_monsters.exists?(dex_no: dex_no)
  end

  def create_monster(species)
    @user.user_monsters.create!(
      monster_species: species,
      dex_no: species.dex_no,
      obtained_at: Time.current
    )
  end

  def resolve_dex_no(identifier)
    if identifier.is_a?(Integer) || identifier.to_s.match?(/\A\d+\z/)
      identifier.to_i
    else
      MonsterSpecies.find_by(key: identifier.to_s)&.dex_no
    end
  end
end
