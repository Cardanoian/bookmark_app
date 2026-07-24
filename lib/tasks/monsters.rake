require "fileutils"
require "open3"
require "tempfile"
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

  desc "Re-evaluate monster unlocks for every existing student (backfill after unlock rollout)"
  task backfill_unlocks: :environment do
    # 기존 학생 전원에게 해금 조건을 한 번 재평가한다(monster_unlocks.md §5 배치 처리). 멱등 —
    # (user_id, dex_no) 유니크 + discover 미보유 가드로 재실행해도 중복 지급되지 않는다. 대량 일괄
    # 발견 알림 큐/연출은 후속(MVP 는 조용한 지급 + 도감 반영). 게임 조건 라인은 과거 플레이가 원장에
    # 없어 즉시 해금되지 않을 수 있다(신규 game_plays 부터 누적).
    students = 0
    discovered = 0
    User.student.find_each do |student|
      students += 1
      discovered += MonsterUnlock.new(student).evaluate!.size
    end
    puts "Backfilled monster unlocks: #{students} students evaluated, #{discovered} monsters newly discovered."
  end

  desc "Install 256px static PNG and animated WebP monster assets under app/assets/images/monsters"
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
          animated_source: source_root.join("webp", format("%02d_%02d.webp", dex_no, stage)),
          reference_directory: source_root.join(format("%02d", dex_no), format("%02d_%s", stage, name)),
          static_destination: destination_root.join("#{key}.png"),
          animated_destination: destination_root.join("#{key}.webp")
        }
      end
    end

    errors = []
    errors << "expected 72 forms in #{seed_path}, found #{assets.size}" unless assets.size == 72

    duplicate_keys = assets.map { |asset| asset[:key] }.tally.select { |_key, count| count > 1 }.keys
    errors << "duplicate image keys: #{duplicate_keys.join(', ')}" if duplicate_keys.any?

    assets.each do |asset|
      errors << "invalid image key: #{asset[:key].inspect}" unless asset[:key].match?(/\A[a-z0-9_]+\z/)
      errors << "missing animated source: #{asset[:animated_source]}" unless asset[:animated_source].file?
      errors << "name mapping mismatch: missing #{asset[:reference_directory]}" unless asset[:reference_directory].directory?
      errors << "missing static source: #{asset[:reference_directory].join("sprite.png")}" unless asset[:reference_directory].join("sprite.png").file?
    end

    abort "Monster asset validation failed:\n- #{errors.join("\n- ")}" if errors.any?
    abort "Monster asset installation requires ffmpeg" unless system("ffmpeg", "-version", out: File::NULL, err: File::NULL)

    FileUtils.mkdir_p(destination_root)
    copied = 0
    skipped = 0

    assets.each do |asset|
      animated_destination = asset[:animated_destination]
      if animated_destination.file? && FileUtils.compare_file(asset[:animated_source], animated_destination)
        skipped += 1
      else
        FileUtils.cp(asset[:animated_source], animated_destination)
        copied += 1
      end

      static_temp = Tempfile.new([ "monster-static-", ".png" ], destination_root)
      static_temp.close
      _stdout, stderr, status = Open3.capture3(
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", asset[:reference_directory].join("sprite.png").to_s,
        "-filter_complex", "[0:v]scale=230:224:force_original_aspect_ratio=decrease:flags=lanczos,pad=256:256:(ow-iw)/2:256-ih-6:color=black@0",
        "-frames:v", "1", "-c:v", "png", static_temp.path
      )
      abort "Could not create static PNG for #{asset[:key]}: #{stderr}" unless status.success?

      static_destination = asset[:static_destination]
      if static_destination.file? && FileUtils.compare_file(static_temp.path, static_destination)
        skipped += 1
      else
        FileUtils.mv(static_temp.path, static_destination)
        copied += 1
      end
      static_temp.unlink if File.exist?(static_temp.path)
    end

    puts "Installed monster assets: copied #{copied}, skipped #{skipped}, total #{assets.size} static PNG + #{assets.size} animated WebP."
  end
end
