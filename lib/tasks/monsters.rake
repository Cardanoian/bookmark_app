# Phase 1 몬스터 도감 시드: docs/monsters.md §7 YAML → monster_species.
# 실제 적재 로직은 MonsterSeeder(테스트와 공유). 여기서는 CLI 진입점만 담당.
namespace :monsters do
  desc "Seed Phase 1 monster species (12 lines x 3 stages = 36 forms)"
  task seed: :environment do
    seeded = MonsterSeeder.seed_phase1!
    puts "Seeded monster species (this run: #{seeded}). MonsterSpecies.count = #{MonsterSpecies.count}"
  end
end
