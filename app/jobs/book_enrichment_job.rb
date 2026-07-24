# 도서 장르 오프라인 보강 잡(WS-D2). SearchService 가 신규 도서를 캐시(:searched)로 유입시킬 때
# perform_later(book.id) 로 예약한다. 이미 장르가 분류된 이웃 도서들에서 Books::GenreInference
# (무API·가중 n-gram 코사인 kNN + 규칙 폴백)로 장르를 추론해 채운다.
#
# 계약:
#   - **멱등**: 이미 genre 가 있는 도서는 손대지 않는다(재실행·경쟁 안전).
#   - **외부 호출 0**: 순수 오프라인 추론. 네트워크/AI 를 부르지 않는다.
#   - 분류된 이웃이 없거나 추론 실패면 아무것도 하지 않는다(도서는 무장르로 남는다).
class BookEnrichmentJob < ApplicationJob
  queue_as :default

  # 이웃(이미 분류된 도서) 표본 상한. 대형 카탈로그(수천 행)에서도 인덱스 빌드를 유계로 유지한다.
  NEIGHBOR_SAMPLE = 1_000

  def perform(book_id)
    book = Book.find_by(id: book_id)
    return if book.nil? || book.genre.present?

    neighbors = Book.where.not(genre: [ nil, "" ]).where.not(id: book.id).limit(NEIGHBOR_SAMPLE).to_a
    return if neighbors.empty?

    result = Books::GenreInference.new(neighbors).infer(book)
    genre = result.genre
    return if genre.blank?

    # 그 사이 다른 경로(seed_full·enrich 등)가 genre 를 채웠으면 덮어쓰지 않는다.
    book.update(genre: genre) if book.reload.genre.blank?
  end
end
