# 온디맨드 게임 콘텐츠 warm 사전생성(Phase 3 §3.5, A5). 카탈로그(추천/고전) 도서를 대상으로
# band×content_axis 워밍 잡을 미리 큐잉해, 학생 첫 플레이의 콜드-첫-오프라인 노출(특히
# matching/hint_reveal)을 최소화한다. 예산·rate limit·스코프 플래그를 준수하며, 무키면 아무것도
# 적재하지 않는다(오프라인만). dedup(이미 워밍 중/AI 게시됨)은 GenerateGameContentJob 이 자체 가드.
namespace :games do
  desc "Warm on-demand game content for catalog books (band × content_axis)"
  task warm: :environment do
    books = Book.where(category: [ :recommended, :classic ])
    total = books.sum { |book| Games::ContentProvider.warm!(book) }
    puts "Enqueued #{total} warming jobs across #{books.count} catalog books."
  end

  # Gemini 줄거리 벌크 백필(Phase 4 §1d). 줄거리도 없고 Gemini 확인도 안 한 카탈로그 도서에
  # BookSummaryJob 을 예산 하 페이싱해 큐잉한다(고전 우선). 무키면 아무것도 적재하지 않는다
  # (오프라인만 — 잡이 무키 no-op 이라 안전하지만, 무의미한 큐잉을 애초에 막는다). 잡이 멱등이라
  # 재실행 안전(이미 채워졌거나 확인한 책은 skip). 시드 아닌 운영 태스크(스케줄/수동 실행).
  desc "Backfill Gemini-generated summaries for known catalog books (confidence-gated, no-op without a key)"
  task backfill_book_summaries: :environment do
    unless Ai::GeminiClient.available?
      puts "Gemini API key not configured — no summaries backfilled (offline)."
      next
    end

    limiter = RateLimiter.new
    budget_key = "book_summary:backfill:#{Time.current.strftime('%Y%m%d')}"
    enqueued = 0
    Book.where(category: [ :classic, :recommended ])
        .where(summary: [ nil, "" ], summary_checked_at: nil)
        .order(category: :desc, id: :asc) # classic(1) 을 recommended(0) 보다 먼저
        .find_each do |book|
      break unless limiter.allow?(budget_key, **RateLimiter::WARMING_DAILY_BUDGET)

      BookSummaryJob.perform_later(book.id)
      enqueued += 1
    end
    puts "Enqueued #{enqueued} book-summary jobs."
  end

  # 콘텐츠 건강 스냅샷(게임 재구성 Phase 5 §7·§8). Phase 0 베이스라인을 건너뛰었으므로 before/after
  # 비교가 아니라 **현재 콘텐츠 건강의 읽기 전용 스냅샷**(운영 모니터링용)이다. 신규 테이블 없이 기존
  # substrate(Quiz·QuizQuestion·QuizReport·GamePlay·QuizContribution·Book·moderation_reject 캐시)만
  # 집계한다. 무키·빈 데이터에서도 크래시 0(0/빈 값이 정상 출력). 쓰기 없음.
  desc "Read-only content-health snapshot (serving-source mix, moderation, reports, summary/game coverage, contributions)"
  task content_health: :environment do
    axes = %i[mcq hint_reveal] # 활성 콘텐츠축 2종(§2)
    # Rails 8.1 은 enum 의 복수형 클래스 헬퍼(Quiz.content_axes)를 기본 정의하지 않으므로 정수 매핑은
    # defined_enums 로 직접 읽는다(집계 그룹 키가 raw 정수라 이 매핑으로 이름을 붙인다).
    axis_ids = Quiz.defined_enums["content_axis"]       # {"mcq"=>0, ...}
    source_ids = QuizQuestion.defined_enums["source"]    # {"offline"=>2, ...}
    status_ids = QuizContribution.defined_enums["status"]
    system_origin = Quiz.defined_enums["origin"]["system"]
    ready_status = Quiz.defined_enums["generation_status"]["ready"]
    pct = ->(part, whole) { whole.to_i.zero? ? "0.0%" : format("%.1f%%", 100.0 * part / whole) }

    puts "== 게임 콘텐츠 건강 스냅샷 (#{Time.current.strftime('%Y-%m-%d %H:%M')}) =="
    puts "Gemini 키: #{Ai::GeminiClient.available? ? '설정됨' : '없음(오프라인)'}"

    # ① 축별 서빙 소스 분포 — ready·미신고 system 퀴즈의 quiz_questions 를 source 별 카운트.
    puts "\n[1] 축별 서빙 소스 분포 (ready·미신고 system 퀴즈 문항)"
    source_mix = QuizQuestion.joins(:quiz)
                             .where(quizzes: { origin: system_origin, generation_status: ready_status, reported: false })
                             .group("quizzes.content_axis", "quiz_questions.source")
                             .count
    axes.each do |axis|
      axis_int = axis_ids[axis.to_s]
      per_source = source_mix.select { |(a, _s), _c| a == axis_int }
      total = per_source.values.sum
      breakdown = %i[offline ai contributed].map do |src|
        count = source_mix.fetch([ axis_int, source_ids[src.to_s] ], 0)
        "#{src}=#{count}"
      end.join(" · ")
      puts "  #{axis}: 총 #{total}문항 (#{breakdown})"
    end

    # ② moderation_reject 캐시 카운터(있으면) 축별 — generate_game_content_job#reject! 가 증가시킴.
    puts "\n[2] 게시 전 moderation 거부 카운터 (축별, 캐시)"
    axes.each do |axis|
      value = begin
        Rails.cache.read("games:moderation_reject:#{axis}")
      rescue StandardError
        nil
      end
      puts "  #{axis}: #{value || 0}"
    end

    # ③ 신고 총계 + 신고율 프록시(quiz_reports / game_plays 근사).
    puts "\n[3] 콘텐츠 신고 (quiz_reports)"
    total_reports = QuizReport.count
    total_game_plays = GamePlay.count
    reports_by_axis = QuizReport.joins(:quiz)
                                .where(quizzes: { origin: system_origin })
                                .group("quizzes.content_axis")
                                .count
    puts "  총 신고: #{total_reports} · 총 game_plays: #{total_game_plays} · 신고율 프록시: #{pct.call(total_reports, total_game_plays)}"
    axes.each do |axis|
      count = reports_by_axis.fetch(axis_ids[axis.to_s], 0)
      puts "  #{axis}(system): #{count} (#{pct.call(count, total_game_plays)} of plays)"
    end

    # ④ summary 커버리지 — Gemini 아는 책 / 모르는 책(확인했으나 blank) / 미확인.
    puts "\n[4] 줄거리(summary) 커버리지 (전체 도서)"
    total_books = Book.count
    has_summary = Book.where.not(summary: [ nil, "" ]).count
    checked_blank = Book.where(summary: [ nil, "" ]).where.not(summary_checked_at: nil).count
    unchecked = Book.where(summary: [ nil, "" ], summary_checked_at: nil).count
    puts "  전체: #{total_books}"
    puts "  줄거리 있음: #{has_summary} (#{pct.call(has_summary, total_books)})"
    puts "  Gemini 모름(확인·blank): #{checked_blank} (#{pct.call(checked_blank, total_books)})"
    puts "  미확인: #{unchecked} (#{pct.call(unchecked, total_books)})"

    # ⑤ 기여 현황 — QuizContribution status 별.
    puts "\n[5] 학생 기여 현황 (quiz_contributions)"
    contributions = QuizContribution.group("status").count # raw 정수 키
    %w[pending approved rejected].each do |status|
      puts "  #{status}: #{contributions.fetch(status_ids[status], 0)}"
    end

    # ⑥ 게임 가용성 커버리지 — 카탈로그(recommended+classic) 중 축별 game_content_available? 비율.
    #    user 인자를 요구하는 game_content_available? 대신 substrate 로 전 밴드 합산 판정한다:
    #    AI-적격(classic 또는 summary 존재) 또는 (책·축)에 실질 콘텐츠(ai/contributed) 세트가 어느
    #    밴드에든 하나라도 있으면 가용(union across bands — 대표 밴드보다 관대·합리적 상한).
    puts "\n[6] 게임 가용성 커버리지 (카탈로그: recommended+classic)"
    catalog = Book.where(category: [ :recommended, :classic ])
    catalog_total = catalog.count
    catalog_ids = catalog.pluck(:id).to_set
    ai_eligible_ids = catalog.where(category: :classic).pluck(:id)
    ai_eligible_ids |= catalog.where.not(summary: [ nil, "" ]).pluck(:id)
    axes.each do |axis|
      substantive_ids = Quiz.where(origin: system_origin, generation_status: ready_status,
                                   reported: false, content_axis: axis_ids[axis.to_s])
                            .joins(:quiz_questions)
                            .where(quiz_questions: { source: [ source_ids["ai"], source_ids["contributed"] ] })
                            .distinct.pluck(:book_id).compact.select { |id| catalog_ids.include?(id) }
      available = (ai_eligible_ids | substantive_ids).size
      puts "  #{axis}: #{available}/#{catalog_total} 가용 (#{pct.call(available, catalog_total)})"
    end
  end
end
