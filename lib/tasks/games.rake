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
end
