# books:seed_full 은 db/seeds/elementary_books.tsv(script/build_elementary_books_tsv.rb 산출물,
# 8,502행)의 유효 ISBN 행만 오프라인·멱등 적재한다. books:seed 는 호환 태스크명으로
# 이 정본 로더에 위임하며, 파일이 없으면 제목-only 축소 카탈로그를 만들지 않는다.
require "csv"
require "yaml"
require "set"

namespace :books do
  # db/seeds/elementary_books.tsv 경로. 테스트는 ENV["BOOKS_TSV"] 로 fixture 를 주입한다.
  def elementary_books_tsv_path
    ENV["BOOKS_TSV"].presence || Rails.root.join("db/seeds/elementary_books.tsv").to_s
  end

  # ── Gemini 줄거리 YAML 시드(db/seeds/book_summaries.yml) 공용 유틸 ─────────────────
  # 이 YAML 은 BookSummaryJob 이 세팅한 **Gemini 생성 요약만**(summary_checked_at present) 담는
  # 시드 자산이다. 무키 배포도 books:seed_summaries 로 이 텍스트를 주입해 접지 요약을 확보한다.
  # 네이버 blurb(summary 있음·checked_at nil)는 별개라 담지 않는다(부호 구분 = summary_checked_at).
  # 테스트는 ENV["BOOK_SUMMARIES_YML"] 로 경로를 주입한다.
  # (상수 대신 메서드로 둔다 — 테스트가 load_tasks 를 반복 호출해도 상수 재초기화 경고가 없게.)
  def book_summaries_header
    <<~HEADER
      # 자동 생성 파일 — Gemini(gemini-2.5-flash)가 만든 도서 줄거리 시드 자산입니다.
      #   내보내기(부트스트랩): bin/rails books:export_summaries       (무키·무네트워크, 현재 DB의 Gemini 요약 export)
      #   갱신: bin/rails books:generate_summaries[limit]             (Gemini 키 필요·네트워크·동기)
      #   로드: bin/rails books:seed_summaries                        (무키·무네트워크·멱등)
      # 수동 편집을 지양하세요. 키 = 정규화 ISBN-13(13자리 문자열) → { title, summary }.
    HEADER
  end

  def book_summaries_yml_path
    ENV["BOOK_SUMMARIES_YML"].presence || Rails.root.join("db/seeds/book_summaries.yml").to_s
  end

  # 파일이 없거나 비었거나 깨졌으면 {} 반환(크래시 0). 반환은 문자열 키 Hash(isbn => {"title","summary"}).
  def read_book_summaries
    path = book_summaries_yml_path
    return {} unless File.exist?(path)

    data = YAML.safe_load_file(path, aliases: false)
    data.is_a?(Hash) ? data : {}
  rescue Psych::Exception
    {}
  end

  # ISBN 정렬 + 헤더 주석과 함께 덮어쓴다(결정적 출력으로 재실행 diff 최소화).
  def write_book_summaries(data)
    sorted = data.sort_by { |isbn, _entry| isbn.to_s }.to_h
    File.write(book_summaries_yml_path, book_summaries_header + YAML.dump(sorted))
  end

  # 현재 DB 의 Gemini 생성 요약(summary_checked_at present·summary 존재)을 기존 YAML 에 병합해 쓴다.
  # 네이버 blurb(checked_at nil)는 제외한다. 부트스트랩·crash-safe 재수출의 단일 로직.
  def export_gemini_summaries
    data = read_book_summaries
    Book.where.not(summary_checked_at: nil).where.not(summary: [ nil, "" ])
        .order(:isbn).find_each do |book|
      next if book.isbn.blank?

      data[book.isbn] = { "title" => book.title, "summary" => book.summary }
    end
    write_book_summaries(data)
    data
  end

  # ── 큐레이션 게임 문항 YAML 시드(db/seeds/book_quizzes.yml) 공용 유틸(Stage 2) ─────────────
  # 이 YAML 은 Sonnet 팀이 도서 줄거리 기반으로 생성한 검수 문항(ISBN-13 → {title, mcq[5],
  # hint_reveal[3]})을 담는다. books:seed_quizzes 가 CuratedQuiz 로 물질화한다(무네트워크·멱등).
  # 테스트는 ENV["BOOK_QUIZZES_YML"] 로 경로를 주입한다.
  def book_quizzes_yml_path
    ENV["BOOK_QUIZZES_YML"].presence || Rails.root.join("db/seeds/book_quizzes.yml").to_s
  end

  # 파일이 없거나 비었거나 깨졌으면 {} 반환(크래시 0). 반환은 문자열 키 Hash(isbn => {title, mcq, hint_reveal}).
  def read_book_quizzes
    path = book_quizzes_yml_path
    return {} unless File.exist?(path)

    data = YAML.safe_load_file(path, aliases: false)
    data.is_a?(Hash) ? data : {}
  rescue Psych::Exception
    {}
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
        # 시리즈 별권 구분용 권차(book_search_series.md). TSV 값은 순수 숫자거나 공란이다.
        # 숫자면 정수로, 공란·비숫자면 nil(단권·권차 없음)로 둔다.
        raw_volume = row["volume"].to_s.strip
        volume = raw_volume.match?(/\A\d+\z/) ? raw_volume.to_i : nil

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
        # volume 은 TSV 가 권차의 단일 진실이라 값 유무와 무관하게 대입한다(공란=nil=단권).
        # 재실행 시 같은 값으로 수렴해 멱등하고, 시리즈 별권을 화면에서 구분할 근거가 된다.
        book.volume = volume
        book.save!

        processed += 1
        puts "  ...#{processed} rows" if (processed % 1000).zero?
      end
    end

    puts "Loaded #{processed} rows from #{path}. recommended=#{Book.recommended.count} classic=#{Book.classic.count} total=#{Book.count}"
    puts "Skipped #{skipped_missing_isbn} rows without ISBN."
    puts "Skipped #{skipped_invalid_isbn} rows with invalid ISBN."
    puts "Dropped columns (no matching books schema field: rank/loans/kdc/monster_element/topic_tags 등) were not saved (volume 은 이제 적재됨)."
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

  # 부트스트랩·재수출(Phase 4 후속): 현재 DB 의 Gemini 생성 요약을 db/seeds/book_summaries.yml 로
  # 내보낸다. 무키·무네트워크(DB 읽고 YAML 쓰기만)라 언제든 안전하게 실행 가능하며, generate_summaries
  # 의 crash-safe 재기록과 동일한 export 로직을 단독 실행한다(초기 파일 부트스트랩 담당).
  desc "Export DB Gemini-generated summaries (summary_checked_at present) to db/seeds/book_summaries.yml (offline)"
  task export_summaries: :environment do
    data = export_gemini_summaries
    puts "books:export_summaries — wrote #{data.size} summaries to #{book_summaries_yml_path}."
  end

  # 저장된 Gemini 요약을 매칭 도서에 주입한다. **summary 가 blank 인 책만** summary+summary_checked_at
  # 을 세팅(checked_at 을 함께 세팅해 게이트가 "확인·앎"으로 인식, 재확인 안 하게). 순수 로컬·무네트워크
  # ·멱등(Gemini 호출 0). YAML 없음/빈 경우 0건 처리, ISBN 매칭 안 되는 항목은 skip(로그). db:seed 배선.
  desc "Load stored Gemini summaries from db/seeds/book_summaries.yml into matching books (offline, idempotent, no network)"
  task seed_summaries: :environment do
    data = read_book_summaries
    if data.empty?
      puts "books:seed_summaries — nothing to load (#{book_summaries_yml_path} missing or empty)."
      next
    end

    applied = 0
    skipped_present = 0
    skipped_no_match = 0
    data.each do |raw_isbn, entry|
      summary = entry.is_a?(Hash) ? entry["summary"].to_s : ""
      next if summary.blank?

      isbn = Books::Isbn.normalize(raw_isbn) || raw_isbn.to_s
      book = Book.find_by(isbn: isbn)
      if book.nil?
        skipped_no_match += 1
        next
      end
      if book.summary.present? # blank 인 책만 채운다(멱등·기존 요약 보존)
        skipped_present += 1
        next
      end

      book.update(summary: summary, summary_checked_at: Time.current)
      applied += 1
    end
    puts "books:seed_summaries — applied=#{applied} skipped_present=#{skipped_present} " \
         "skipped_no_match=#{skipped_no_match} (of #{data.size} entries)."
  end

  # db/seeds/book_quizzes.yml(Sonnet 팀 검수 문항)을 CuratedQuiz 로 물질화한다(Stage 2). 축별
  # (mcq/hint_reveal) payload 를 find_or_initialize_by 로 멱등 upsert 하고, 그 책에 큐레이션이
  # **이번에 처음** 도입되면(had=false) 기존 origin=system Quiz(제네릭 offline·미검증 ai 캐시)를
  # 은퇴시켜 다음 플레이가 큐레이션으로 물질화되게 한다(prod 최초 seed 는 플레이 전이라 no-op).
  # **이미 큐레이션 도입된 책(had=true)은 재실행 시 은퇴 스킵**(멱등·attempt 보존). 무네트워크·멱등.
  # YAML 없음/빈 경우 0건 처리(크래시 0), ISBN 미매칭 skip(카운트). `ENV["BOOK_QUIZZES_YML"]` 주입.
  desc "Load curated book quizzes from db/seeds/book_quizzes.yml into curated_quizzes (offline, idempotent, no network)"
  task seed_quizzes: :environment do
    data = read_book_quizzes
    if data.empty?
      puts "books:seed_quizzes — nothing to load (#{book_quizzes_yml_path} missing or empty)."
      next
    end

    applied = 0
    skipped_no_match = 0
    retired_books = 0
    data.each do |raw_isbn, entry|
      next unless entry.is_a?(Hash)

      isbn = Books::Isbn.normalize(raw_isbn) || raw_isbn.to_s
      book = Book.find_by(isbn: isbn)
      if book.nil?
        skipped_no_match += 1
        next
      end

      had = CuratedQuiz.exists?(book_id: book.id) # 최초 도입 판정(축 upsert 전에 스냅샷)

      %w[mcq hint_reveal].each do |axis|
        payload = entry[axis]
        next if payload.blank?

        curated = CuratedQuiz.find_or_initialize_by(book_id: book.id, content_axis: axis)
        curated.payload = payload
        curated.save!
        applied += 1
      end

      # 최초 도입이고 그 책에 origin=system Quiz 가 있으면 은퇴(제네릭 offline/미검증 ai 캐시 제거 →
      # 다음 플레이가 큐레이션으로 물질화). 이미 큐레이션 도입된 책은 재실행 시 은퇴 스킵(멱등·attempt 보존).
      if !had && Quiz.where(origin: :system, book_id: book.id).exists?
        Quiz.where(origin: :system, book_id: book.id).destroy_all
        retired_books += 1
      end
    end

    puts "books:seed_quizzes — applied=#{applied} skipped_no_match=#{skipped_no_match} " \
         "retired_books=#{retired_books} (of #{data.size} entries)."
  end

  # 카탈로그 도서(classic/recommended) 중 ① summary blank ② summary_checked_at nil ③ YAML 미포함 ISBN
  # 인 책에 대해 limit 개(+ 일일 예산)만큼 Gemini 요약을 **동기 생성**하고 YAML 을 갱신한다. 무키면 skip.
  # ⚠️ dev 큐 어댑터(async)에서 perform_later 는 프로세스 종료 시 유실되므로 반드시 perform_now(동기)로
  # 이 프로세스 안에서 Gemini 호출·DB 반영을 완결한다. 각 known 직후 YAML rewrite(crash-safe). 네트워크
  # 는 이 태스크에서만 발생(seed_summaries·앱 런타임은 무네트워크). 시드 아닌 운영 태스크(수동 실행).
  desc "Generate Gemini summaries for catalog books lacking them and persist to YAML (networked, synchronous; no-op without a key)"
  task :generate_summaries, [ :limit ] => :environment do |_task, args|
    unless Ai::GeminiClient.available?
      puts "books:generate_summaries — Gemini API key not configured; skipping generation (no network)."
      next
    end

    limit = (args[:limit].presence || 50).to_i
    known_isbns = read_book_summaries.keys.to_set
    limiter = RateLimiter.new
    budget_key = "book_summary:generate:#{Time.current.strftime('%Y%m%d')}"

    data = read_book_summaries
    processed = 0
    known = 0
    unknown = 0
    Book.where(category: [ :classic, :recommended ])
        .where(summary: [ nil, "" ], summary_checked_at: nil)
        .order(category: :desc, id: :asc) # classic(1) 을 recommended(0) 보다 먼저
        .find_each do |book|
      break if processed >= limit
      next if book.isbn.present? && known_isbns.include?(book.isbn) # ③ 이미 YAML 에 있으면 skip
      break unless limiter.allow?(budget_key, **RateLimiter::WARMING_DAILY_BUDGET)

      # 동기 처리(perform_now) — async perform_later 금지(프로세스 종료 시 잡 유실).
      BookSummaryJob.perform_now(book.id)
      book.reload
      processed += 1

      if book.summary.present? && book.summary_checked_at.present?
        data[book.isbn] = { "title" => book.title, "summary" => book.summary }
        write_book_summaries(data) # 각 known 직후 rewrite — 중단돼도 진행분 보존(crash-safe)
        known += 1
        puts "  [known]   #{book.title} (#{book.isbn})"
      else
        unknown += 1 # 모르는 책: 잡이 checked_at 만 세팅 → 다음 run 재처리 skip(YAML 미포함)
        puts "  [unknown] #{book.title} (#{book.isbn})"
      end
    end
    puts "books:generate_summaries — processed=#{processed} known=#{known} unknown=#{unknown}; " \
         "YAML now has #{data.size} entries."
  end
end
