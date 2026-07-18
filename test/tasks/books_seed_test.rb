require "test_helper"
require "rake"
require "tempfile"
require "csv"

class BooksSeedTest < ActiveSupport::TestCase
  HEADERS = %w[title author publisher isbn13 project_category cover_url primary_grade_band].freeze

  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("books:seed")
    @tsv = Tempfile.new([ "books_seed", ".tsv" ])
    CSV.open(@tsv.path, "w", col_sep: "\t") do |csv|
      csv << HEADERS
      Book::GRADE_BANDS.each_with_index do |band, index|
        csv << [ "밴드책#{index}", "작가", "출판사", TestBookIsbn.next,
                 index == 2 ? "classic" : "recommended", "", band ]
      end
    end
  end

  teardown do
    @tsv&.close!
  end

  test "ISBN이 있는 전량 TSV를 유일한 카탈로그 소스로 적재한다" do
    run_seed!

    assert_equal Book::GRADE_BANDS.sort, Book.order(:grade_band).pluck(:grade_band).sort
    assert_equal 2, Book.recommended.count
    assert_equal 1, Book.classic.count
  end

  test "재실행해도 ISBN 기준으로 중복 등록하지 않는다" do
    run_seed!
    count = Book.count

    run_seed!

    assert_equal count, Book.count
  end

  test "TSV가 없으면 제목만 있는 축소 카탈로그를 만들지 않는다" do
    missing = "/tmp/does-not-exist-#{SecureRandom.hex(4)}.tsv"

    out, = run_seed!(missing)

    assert_match(/skipped/, out)
    assert_equal 0, Book.count
  end

  private

  def run_seed!(path = @tsv.path)
    ENV["BOOKS_TSV"] = path
    Rake::Task["books:seed"].reenable
    Rake::Task["books:seed_full"].reenable
    capture_io { Rake::Task["books:seed"].invoke }
  ensure
    ENV.delete("BOOKS_TSV")
  end
end
