require "test_helper"

class RecommendationCoverEnrichmentJobTest < ActiveJob::TestCase
  teardown { RecommendationCoverEnrichmentJob.reset_factory! }

  test "enriches only books with a blank cover from the requested import" do
    recommendation_import = RecommendationImport.create!(
      filename: "recommendations.xlsx",
      file_digest: "cover-job-digest",
      imported_at: Time.current
    )
    missing = Book.create!(title: "표지 없는 책", isbn: "9791111111112")
    covered = Book.create!(title: "표지 있는 책", isbn: "9792222222223", cover_url: "https://img/cover")
    recommendation_import.book_recommendations.create!(book: missing, section: "어린이문학", position: 1)
    recommendation_import.book_recommendations.create!(book: covered, section: "어린이문학", position: 2)
    recommendation_import.update!(item_count: 2)

    enriched_ids = []
    fake_enricher = Object.new
    fake_enricher.define_singleton_method(:enrich) do |scope|
      enriched_ids.concat(scope.ids)
    end

    RecommendationCoverEnrichmentJob.enricher_factory = -> { fake_enricher }
    RecommendationCoverEnrichmentJob.perform_now(recommendation_import.id)

    assert_equal [ missing.id ], enriched_ids
  end

  test "ignores a deleted import" do
    assert_nothing_raised { RecommendationCoverEnrichmentJob.perform_now(-1) }
  end
end
