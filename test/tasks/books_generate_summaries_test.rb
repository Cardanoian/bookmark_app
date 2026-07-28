require "test_helper"
require "rake"
require "tempfile"
require "yaml"

# books:generate_summaries 검증(Claude 줄거리 생성 → YAML+DB 기록). 스텁 ClaudeClient/BookSummaryService
# (book_summary_job_test 의 stub_new 선례)로 실제 Claude 호출 없이: 무키→skip, known→YAML+DB, 모름→
# checked_at 만·YAML 미포함, YAML 이미 포함분 skip, limit 준수, 동기(perform_now) 처리를 검증한다.
class BooksGenerateSummariesTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("books:generate_summaries")
    @yml = Tempfile.new([ "book_summaries", ".yml" ])
    ENV["BOOK_SUMMARIES_YML"] = @yml.path
  end

  teardown do
    ENV.delete("BOOK_SUMMARIES_YML")
    @yml&.close!
  end

  def generate!(limit = nil)
    Rake::Task["books:generate_summaries"].reenable
    capture_io { Rake::Task["books:generate_summaries"].invoke(limit) }
  end

  def yaml_data
    return {} unless File.exist?(@yml.path)

    YAML.safe_load_file(@yml.path, aliases: false) || {}
  end

  # ── 무키: 생성 skip(test_helper 가 Claude 키 공란 강제 → available? false) ──
  test "with no API key it skips generation without touching the DB" do
    book = Book.create!(title: "무키책", isbn: TestBookIsbn.next, category: :classic)

    out, = generate!

    assert_match(/not configured/, out)
    assert_nil book.reload.summary_checked_at
  end

  # ── 키 있음 + known: YAML + DB 에 요약 기록 ──
  test "a known book is written to both YAML and the DB" do
    book = Book.create!(title: "known-책", isbn: TestBookIsbn.next, category: :classic)

    with_stub { generate!(10) }

    book.reload
    assert_equal "생성된 줄거리", book.summary
    assert_not_nil book.summary_checked_at
    assert_equal "생성된 줄거리", yaml_data[book.isbn]["summary"]
  end

  # ── 키 있음 + 모름: checked_at 만 세팅, YAML 에 넣지 않는다 ──
  test "an unknown book stamps checked_at only and is not written to YAML" do
    book = Book.create!(title: "unknown-책", isbn: TestBookIsbn.next, category: :classic)

    with_stub { generate!(10) }

    book.reload
    assert_nil book.summary, "모르는 책은 줄거리를 채우지 않는다(환각 방지)"
    assert_not_nil book.summary_checked_at, "모르는 책도 확인 시각을 남겨 재확인을 막는다"
    assert_not yaml_data.key?(book.isbn)
  end

  # ── YAML 에 이미 있는 ISBN 은 대상에서 제외(③) ──
  test "books whose ISBN is already in the YAML are skipped" do
    isbn = TestBookIsbn.next
    book = Book.create!(title: "known-이미있음", isbn: isbn, category: :classic)
    File.write(@yml.path, YAML.dump(isbn => { "title" => "known-이미있음", "summary" => "기존" }))

    out, = with_stub { generate!(10) }

    assert_nil book.reload.summary_checked_at, "이미 YAML 에 있으면 재처리하지 않는다"
    assert_match(/processed=0/, out)
    assert_equal "기존", yaml_data[isbn]["summary"]
  end

  # ── limit 준수: 후보가 많아도 limit 개만 처리 ──
  test "limit caps the number of processed books" do
    3.times { |i| Book.create!(title: "known-#{i}", isbn: TestBookIsbn.next, category: :classic) }

    out, = with_stub { generate!(1) }

    assert_match(/processed=1\b/, out)
  end

  private

  # 스텁 BookSummaryService: 제목에 "unknown" 이 들어가면 nil(모름), 아니면 줄거리(known).
  class StubService
    def call(book)
      book.title.include?("unknown") ? nil : "생성된 줄거리"
    end
  end

  # ClaudeClient.new 을 configured?=true 로, BookSummaryService.new 을 스텁으로 임시 교체한다
  # (Minitest 6 은 minitest/mock 미제공 — book_summary_job_test 의 stub_new 선례). BookSummaryJob
  # 내부(ClaudeClient.new.configured? + BookSummaryService.new.call)와 available? 를 모두 커버한다.
  def with_stub
    configured = Object.new
    def configured.configured? = true
    Ai::ClaudeClient.define_singleton_method(:new) { |*, **| configured }
    Ai::BookSummaryService.define_singleton_method(:new) { |*, **| StubService.new }
    yield
  ensure
    Ai::ClaudeClient.singleton_class.send(:remove_method, :new)
    Ai::BookSummaryService.singleton_class.send(:remove_method, :new)
  end
end
