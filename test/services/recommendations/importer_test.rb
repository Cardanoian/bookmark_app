require "test_helper"

class Recommendations::ImporterTest < ActiveJob::TestCase
  test "bundled 2026 recommendation workbook contains 203 elementary books" do
    path = Dir[Rails.root.join("docs", "*.xlsx")].find do |candidate|
      File.basename(candidate).unicode_normalize(:nfc).include?("추천도서목록")
    end
    assert path, "번들 추천도서 XLSX가 있어야 한다"

    reader = Recommendations::XlsxReader.new(path)
    entries = reader.read

    assert_equal 203, entries.size
    assert entries.all? { |entry| entry.section.start_with?("어린이") }
    assert_match "2026 2월호", reader.source_title
  end

  test "imports only elementary sections and upserts books by ISBN" do
    existing = Book.create!(title: "옛 제목", author: "옛 저자", isbn: "9781111111113", category: :searched)
    file = build_recommendation_xlsx([
      { section: "어린이문학", title: "새 제목", author: "새 저자", publisher: "새 출판사", isbn: "9781111111113" },
      { section: "청소년문학", title: "청소년책", author: "작가", publisher: "출판사", isbn: "9782222222224" },
      { section: "어린이과학", title: "과학책", author: "과학자", publisher: "과학사", isbn: "9783333333335" }
    ])

    result = nil
    assert_enqueued_jobs 1, only: RecommendationCoverEnrichmentJob do
      result = import(file)
    end

    assert_not result.reused
    assert_equal 2, result.recommendation_import.item_count
    assert result.recommendation_import.active?
    assert_equal %w[과학책 새\ 제목], result.recommendation_import.books.order(:title).pluck(:title)
    assert_equal "새 제목", existing.reload.title
    assert existing.recommended?
    assert_nil Book.find_by(isbn: "9782222222224")
    assert_enqueued_with job: RecommendationCoverEnrichmentJob,
                         args: [ result.recommendation_import.id ]
  ensure
    file&.close!
  end

  test "enqueues genre enrichment for blank-genre books but skips already-classified ones" do
    classified = Book.create!(title: "장르 있는 책", author: "작가", publisher: "출판사",
                              isbn: "9781111111113", category: :recommended, genre: "문학")
    file = build_recommendation_xlsx([
      { section: "어린이문학", title: "장르 있는 책", author: "작가", publisher: "출판사", isbn: "9781111111113" },
      { section: "어린이과학", title: "새 책", author: "새 작가", publisher: "새 출판사", isbn: "9783333333335" }
    ])

    # 공란 장르 신규 도서 1권만 보강 예약, 이미 장르가 있는 기존 도서는 제외한다.
    assert_enqueued_jobs 1, only: BookEnrichmentJob do
      import(file)
    end

    new_book = Book.find_by(isbn: "9783333333335")
    assert_enqueued_with job: BookEnrichmentJob, args: [ new_book.id ]
    assert_equal "문학", classified.reload.genre
  ensure
    file&.close!
  end

  test "new successful upload replaces active list and same file is idempotent" do
    first_file = build_recommendation_xlsx([
      { section: "어린이문학", title: "첫 책", author: "첫 작가", publisher: "첫 출판사", isbn: "9784444444446" }
    ])
    second_file = build_recommendation_xlsx([
      { section: "어린이인문", title: "둘째 책", author: "둘째 작가", publisher: "둘째 출판사", isbn: "9785555555557" }
    ])
    first = import(first_file).recommendation_import
    second = import(second_file).recommendation_import

    assert_not first.reload.active?
    assert_equal second, RecommendationImport.current

    assert_no_difference -> { RecommendationImport.count } do
      reused = import(second_file)
      assert reused.reused
      assert_equal second, reused.recommendation_import
    end
  ensure
    first_file&.close!
    second_file&.close!
  end

  test "invalid upload leaves current recommendations unchanged" do
    valid_file = build_recommendation_xlsx([
      { section: "어린이그림책", title: "남는 책", author: "작가", publisher: "출판사", isbn: "9786666666668" }
    ])
    current = import(valid_file).recommendation_import
    invalid_file = Tempfile.new([ "invalid", ".xlsx" ])
    invalid_file.write("not a zip")
    invalid_file.flush

    assert_raises(Recommendations::Importer::Error) { import(invalid_file) }
    assert_equal current, RecommendationImport.current
  ensure
    valid_file&.close!
    invalid_file&.close!
  end

  test "rejects an elementary recommendation with a missing ISBN" do
    file = build_recommendation_xlsx([
      { section: "어린이문학", title: "ISBN 없는 추천책", author: "작가", publisher: "출판사", isbn: "" }
    ])

    error = assert_raises(Recommendations::Importer::Error) { import(file) }

    assert_match(/ISBN이 없는 추천도서 1권/, error.message)
    assert_nil Book.find_by(title: "ISBN 없는 추천책")
    assert_equal 0, RecommendationImport.count
  ensure
    file&.close!
  end

  test "rejects an elementary recommendation with an invalid ISBN" do
    file = build_recommendation_xlsx([
      { section: "어린이문학", title: "ISBN 오류 추천책", author: "작가", publisher: "출판사", isbn: "9781111111110" }
    ])

    error = assert_raises(Recommendations::Importer::Error) { import(file) }

    assert_match(/유효하지 않은 ISBN 추천도서 1권/, error.message)
    assert_nil Book.find_by(title: "ISBN 오류 추천책")
  ensure
    file&.close!
  end

  private

  def import(file)
    Recommendations::Importer.new(path: file.path, filename: "recommendations.xlsx").call
  end
end
