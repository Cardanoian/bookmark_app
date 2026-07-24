# 반려 몬스터 도감 시드 로직(docs/monsters.md §7 YAML → monster_species).
# rake `monsters:seed` 와 테스트가 공유하는 단일 진실. 기본은 24라인×3=72폼 전량 적재로
# 도감 완성(dex_complete, 분모 24) 보상 루프가 닫히게 한다. phase 별 부분 적재도 지원
# (에셋 배포를 나눠야 할 때). evolves_from 은 stage 순서로 자동 연결. 멱등(find_or_initialize_by
# key). 적재한 폼 수를 반환한다.
class MonsterSeeder
  SEED_PATH = Rails.root.join("db/seeds/monsters.yml")

  def self.seed_all!
    new.seed_all!
  end

  def self.seed_phase1!
    new.seed_phase1!
  end

  def self.seed_phase2!
    new.seed_phase2!
  end

  # 설계된 24라인(72폼) 전량 적재.
  def seed_all!
    seed_lines(all_lines)
  end

  # Phase 1 라인만(12라인×3=36폼) — 하위호환·부분 배포용.
  def seed_phase1!
    seed_lines(lines_for_phase(1))
  end

  # Phase 2 라인만(12라인×3=36폼) — Phase 1 위에 증분 적재용.
  def seed_phase2!
    seed_lines(lines_for_phase(2))
  end

  private

  def seed_lines(lines)
    seeded = 0
    lines.each do |line|
      previous = nil
      forms_for(line).each do |form|
        previous = seed_form(line, form, previous)
        seeded += 1
      end
    end
    seeded
  end

  def data
    @data ||= YAML.load_file(SEED_PATH)
  end

  def all_lines
    data.fetch("monster_lines")
  end

  def lines_for_phase(phase)
    all_lines.select { |line| line["phase"] == phase }
  end

  def forms_for(line)
    line.fetch("forms").sort_by { |form| form["stage"] }
  end

  def seed_form(line, form, previous)
    species = MonsterSpecies.find_or_initialize_by(key: form["key"])
    species.dex_no = line["dex_no"]
    species.stage = form["stage"]
    species.name = form["name"]
    species.element = line["element"]
    species.rarity = line["rarity"]
    species.evolve_condition = form["evolve_condition"]
    # 해금 조건은 라인 단위 규칙이라 1단계 폼에만 얹는다(monster_unlocks.md §5 — 폼마다 반복 저장 금지).
    # 2·3단계는 nil 로 두어 재시드해도 stage2·3 에 조건이 새지 않게 한다.
    species.unlock_condition = form["stage"] == 1 ? line["unlock_condition"] : nil
    species.image_key = form["key"]
    species.evolves_from = previous
    species.save!
    species
  end
end
