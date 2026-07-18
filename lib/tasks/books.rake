# books:seed_full 은 db/seeds/elementary_books.tsv(script/build_elementary_books_tsv.rb 산출물,
# 8,502행)의 유효 ISBN 행만 오프라인·멱등 적재한다. books:seed 는 호환 태스크명으로
# 이 정본 로더에 위임하며, 파일이 없으면 제목-only 축소 카탈로그를 만들지 않는다.
require "csv"

namespace :books do
  # db/seeds/elementary_books.tsv 경로. 테스트는 ENV["BOOKS_TSV"] 로 fixture 를 주입한다.
  def elementary_books_tsv_path
    ENV["BOOKS_TSV"].presence || Rails.root.join("db/seeds/elementary_books.tsv").to_s
  end

  desc "Seed the ISBN-bearing catalog from the full TSV (compatibility alias)"
  task seed: :environment do
    # ISBN 필수화 이후 제목-only 축소 카탈로그는 더 이상 Book으로 등록하지 않는다.
    # 호환 태스크명은 유지하되, 전량 TSV가 있으면 유일한 정본 로더로 위임한다.
    full_path = elementary_books_tsv_path
    unless File.exist?(full_path)
      puts "books:seed skipped — ISBN-bearing catalog #{full_path} not found."
      next
    end
    Rake::Task["books:seed_full"].reenable
    Rake::Task["books:seed_full"].invoke
  end

  desc "Load the full elementary catalog from db/seeds/elementary_books.tsv (offline, idempotent)"
  task seed_full: :environment do
    path = elementary_books_tsv_path
    unless File.exist?(path)
      puts "books:seed_full skipped — #{path} not found (run script/build_elementary_books_tsv.rb first)."
      next
    end

    # 8,502행 규모라 트랜잭션으로 감싸 원자성·성능을 확보한다.
    processed = 0
    skipped_missing_isbn = 0
    skipped_invalid_isbn = 0
    ActiveRecord::Base.transaction do
      CSV.foreach(path, col_sep: "\t", headers: true) do |row|
        title = row["title"].to_s.strip.presence
        next if title.blank?

        author = row["author"].to_s.strip.presence
        publisher = row["publisher"].to_s.strip.presence
        raw_isbn = row["isbn13"].to_s.strip.presence
        unless raw_isbn
          skipped_missing_isbn += 1
          next
        end
        isbn = Books::Isbn.normalize(raw_isbn)
        unless isbn
          skipped_invalid_isbn += 1
          next
        end
        cover_url = row["cover_url"].to_s.strip.presence
        grade_band = row["primary_grade_band"].to_s.strip.presence
        grade_band = nil unless Book::GRADE_BANDS.include?(grade_band)
        genre = row["genre"].to_s.strip.presence
        genre = nil if genre == "미분류" # 미분류는 무장르로 남겨 BookEnrichmentJob 이 나중에 채우게 둔다
        category = row["project_category"].to_s.strip
        category = %w[recommended classic].include?(category) ? category : "recommended"

        # 같은 isbn 의 선존 행(학생 검색이 만든 :searched 캐시 포함)을 제자리에서 큐레이션으로
        # 승격한다. reports.book_id 링크를 보존하며 ISBN 없는 원본 행은 위에서 등록 제외한다.
        book = Book.find_or_initialize_by(isbn: isbn)

        if book.new_record?
          book.title = title
          book.author = author
          book.isbn = isbn
        end
        # publisher/cover_url/grade_band/genre 는 TSV 값이 있을 때만 대입해 기존값을 비파괴 보존한다.
        # summary 는 TSV 에 없는 컬럼이라 절대 건드리지 않는다(기존 큐레이션 요약 보존).
        book.publisher = publisher if publisher
        book.cover_url = cover_url if cover_url
        book.grade_band = grade_band if grade_band
        book.genre = genre if genre
        book.category = category
        book.save!

        processed += 1
        puts "  ...#{processed} rows" if (processed % 1000).zero?
      end
    end

    puts "Loaded #{processed} rows from #{path}. recommended=#{Book.recommended.count} classic=#{Book.classic.count} total=#{Book.count}"
    puts "Skipped #{skipped_missing_isbn} rows without ISBN."
    puts "Skipped #{skipped_invalid_isbn} rows with invalid ISBN."
    puts "Dropped columns (no matching books schema field: rank/loans/kdc/monster_element/topic_tags 등) were not saved."
  end

  desc "Enrich catalog book covers/publishers by ISBN via Naver, falling back to data4library covers (manual, networked; no-op without keys)"
  task enrich: :environment do
    updated = Books::CatalogEnricher.new.enrich_all
    if Books::SearchService.available? || Library::Data4libraryService.available?
      sources = [ ("Naver" if Books::SearchService.available?), ("data4library" if Library::Data4libraryService.available?) ].compact.join(" + ")
      puts "books:enrich — updated #{updated} catalog books (via #{sources})."
    else
      puts "books:enrich skipped — no Naver/data4library keys (offline). Catalog keeps curated fields."
    end
  end

  desc "Find/merge duplicate books by normalized ISBN and high-confidence blank-ISBN shadows (dry-run by default)"
  task deduplicate_isbn: :environment do
    apply = ENV["APPLY"] == "1"
    include_shadows = ENV.fetch("INCLUDE_SHADOWS", "1") != "0"
    result = Books::Deduplicator.new(apply: apply, include_shadows: include_shadows).call

    puts apply ? "books:deduplicate_isbn — APPLY mode" : "books:deduplicate_isbn — DRY RUN (no DB changes)"
    result.outcomes.each do |outcome|
      group = outcome.group
      duplicate_labels = group.duplicates.map { |book| "##{book.id} #{book.title}" }.join(", ")
      suffix = outcome.reason.present? ? " — #{outcome.reason}" : ""
      puts "  [#{outcome.status}] #{group.kind} #{group.key}: keep ##{group.canonical.id} #{group.canonical.title}; " \
           "remove #{duplicate_labels}#{suffix}"
    end
    puts "Detected=#{result.detected_count} ready=#{result.ready_count} merged=#{result.merged_count} " \
         "deleted=#{result.deleted_count} skipped=#{result.skipped_count} errors=#{result.error_count}"

    unless apply
      puts "No rows changed. Review the list, then run: APPLY=1 bin/rails books:deduplicate_isbn"
    end
    abort "books:deduplicate_isbn completed with errors" if result.error_count.positive?
  end
end
