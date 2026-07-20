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
end
