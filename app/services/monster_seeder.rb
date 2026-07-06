# Phase 1 몬스터 도감 시드 로직(docs/monsters.md §7 YAML → monster_species).
# rake `monsters:seed` 와 테스트가 공유하는 단일 진실. phase:1 라인만 적재(12라인×3=36폼).
# evolves_from 은 stage 순서로 자동 연결. 멱등(find_or_initialize_by key). 적재 폼 수 반환.
class MonsterSeeder
  SEED_PATH = Rails.root.join("db/seeds/monsters.yml")

  def self.seed_phase1!
    new.seed_phase1!
  end

  def seed_phase1!
    seeded = 0
    phase1_lines.each do |line|
      previous = nil
      forms_for(line).each do |form|
        previous = seed_form(line, form, previous)
        seeded += 1
      end
    end
    seeded
  end

  private

  def data
    @data ||= YAML.load_file(SEED_PATH)
  end

  def phase1_lines
    data.fetch("monster_lines").select { |line| line["phase"] == 1 }
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
    species.image_key = form["key"]
    species.evolves_from = previous
    species.save!
    species
  end
end
