# 몬스터 도감 시드: docs/monsters.md §7 YAML → monster_species.
# 실제 적재 로직은 MonsterSeeder(테스트와 공유). 여기서는 CLI 진입점만 담당.
namespace :monsters do
  desc "Seed all monster species (24 lines x 3 stages = 72 forms)"
  task seed: :environment do
    seeded = MonsterSeeder.seed_all!
    puts "Seeded monster species (this run: #{seeded}). MonsterSpecies.count = #{MonsterSpecies.count}"
  end

  desc "Seed only Phase 2 monster species (12 lines x 3 stages = 36 forms) on top of Phase 1"
  task seed_phase2: :environment do
    seeded = MonsterSeeder.seed_phase2!
    puts "Seeded Phase 2 monster species (this run: #{seeded}). MonsterSpecies.count = #{MonsterSpecies.count}"
  end
end
