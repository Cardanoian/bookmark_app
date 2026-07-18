# 공식 추천도서 업로드 직후 표지 결측 도서를 네이버 도서 API로 비동기 보강한다.
# 업로드 트랜잭션 밖에서 enqueue되므로 저장된 추천 목록만 읽으며, CatalogEnricher가
# ISBN 정확 일치·순차 throttle·무키/원격 실패 no-op 계약을 담당한다.
class RecommendationCoverEnrichmentJob < ApplicationJob
  queue_as :default

  class << self
    attr_writer :enricher_factory

    def enricher_factory
      @enricher_factory ||= -> { Books::CatalogEnricher.new }
    end

    def reset_factory!
      @enricher_factory = nil
    end
  end

  def perform(recommendation_import_id)
    recommendation_import = RecommendationImport.find_by(id: recommendation_import_id)
    return if recommendation_import.nil?

    missing_covers = recommendation_import.books.where("cover_url IS NULL OR cover_url = ''")
    self.class.enricher_factory.call.enrich(missing_covers)
  end
end
