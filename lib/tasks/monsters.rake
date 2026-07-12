require "fileutils"
require "yaml"

# 몬스터 도감 시드와 이미지 에셋 설치 진입점.
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

  desc "Install all monster WebP assets under app/assets/images/monsters"
  task install_assets: :environment do
    seed_path = Rails.root.join("db/seeds/monsters.yml")
    source_root = Rails.root.join("script/output")
    destination_root = Rails.root.join("app/assets/images/monsters")
    lines = YAML.load_file(seed_path).fetch("monster_lines")

    assets = lines.flat_map do |line|
      dex_no = Integer(line.fetch("dex_no"))

      line.fetch("forms").map do |form|
        stage = Integer(form.fetch("stage"))
        key = form.fetch("key")
        name = form.fetch("name")

        {
          key: key,
          source: source_root.join("webp", format("%02d_%02d.webp", dex_no, stage)),
          reference_directory: source_root.join(format("%02d", dex_no), format("%02d_%s", stage, name)),
          destination: destination_root.join("#{key}.webp")
        }
      end
    end

    errors = []
    errors << "expected 72 forms in #{seed_path}, found #{assets.size}" unless assets.size == 72

    duplicate_keys = assets.map { |asset| asset[:key] }.tally.select { |_key, count| count > 1 }.keys
    errors << "duplicate image keys: #{duplicate_keys.join(', ')}" if duplicate_keys.any?

    assets.each do |asset|
      errors << "invalid image key: #{asset[:key].inspect}" unless asset[:key].match?(/\A[a-z0-9_]+\z/)
      errors << "missing source: #{asset[:source]}" unless asset[:source].file?
      errors << "name mapping mismatch: missing #{asset[:reference_directory]}" unless asset[:reference_directory].directory?
    end

    abort "Monster asset validation failed:\n- #{errors.join("\n- ")}" if errors.any?

    FileUtils.mkdir_p(destination_root)
    copied = 0
    skipped = 0

    assets.each do |asset|
      if asset[:destination].file? && FileUtils.compare_file(asset[:source], asset[:destination])
        skipped += 1
      else
        FileUtils.cp(asset[:source], asset[:destination])
        copied += 1
      end
    end

    puts "Installed monster assets: copied #{copied}, skipped #{skipped}, total #{assets.size}."
  end
end
