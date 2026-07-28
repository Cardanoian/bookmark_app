require "test_helper"

# Claude 줄거리 생성 백그라운드 잡(게임 재구성 Phase 4 §1c). BookEnrichmentJob 미러.
# 무키 no-op(checked_at 미세팅 → 키 생기면 재시도), 키+known=summary+checked_at, 키+모름=checked_at만
# (재실행 skip), 이미 summary/checked_at=멱등 skip. 네트워크 0·크래시 0.
class BookSummaryJobTest < ActiveJob::TestCase
  setup do
    @book = Book.create!(title: "줄거리잡책", author: "지은이", category: :recommended)
  end

  # ── 무키: no-op, checked_at 을 세팅하지 않는다(키 생기면 나중에 재시도되게) ──
  test "with no API key it is a no-op — summary and checked_at stay nil" do
    BookSummaryJob.perform_now(@book.id)

    @book.reload
    assert_nil @book.summary
    assert_nil @book.summary_checked_at, "무키는 checked_at 을 세팅하지 않는다(영구 무명 마킹 금지)"
  end

  # ── 키 있음 + known: summary + checked_at 저장 ──
  test "with a key and a known book it stores the summary and stamps checked_at" do
    run_with_key(FixedSummary.new("잎싹이 자유를 찾는 이야기예요.")) do
      BookSummaryJob.perform_now(@book.id)
    end

    @book.reload
    assert_equal "잎싹이 자유를 찾는 이야기예요.", @book.summary
    assert_not_nil @book.summary_checked_at
  end

  # ── 키 있음 + 모름(nil): checked_at 만(모르는 책 마킹, 재확인 방지) ──
  test "with a key and an unknown book it stamps checked_at only (marks as unknown)" do
    run_with_key(FixedSummary.new(nil)) do
      BookSummaryJob.perform_now(@book.id)
    end

    @book.reload
    assert_nil @book.summary, "모르는 책은 줄거리를 채우지 않는다(환각 방지)"
    assert_not_nil @book.summary_checked_at, "모르는 책도 확인 시각을 남겨 재확인을 막는다"
  end

  # ── 재실행 멱등: 이미 확인한(checked_at) 책은 서비스를 다시 부르지 않는다 ──
  test "a book already checked is skipped on re-run (idempotent)" do
    @book.update_column(:summary_checked_at, 1.day.ago)

    run_with_key(RaisingService.new) do # 호출되면 raise → 호출 안 됨을 검증
      assert_nothing_raised { BookSummaryJob.perform_now(@book.id) }
    end
    assert_nil @book.reload.summary
  end

  # ── 이미 summary 있는 책은 skip(멱등) ──
  test "a book that already has a summary is skipped" do
    @book.update!(summary: "기존 줄거리")

    run_with_key(RaisingService.new) do
      assert_nothing_raised { BookSummaryJob.perform_now(@book.id) }
    end
    assert_equal "기존 줄거리", @book.reload.summary
  end

  # ── 삭제된 책은 no-op ──
  test "is a no-op when the book was deleted before the job ran" do
    id = @book.id
    @book.destroy!
    assert_nothing_raised { BookSummaryJob.perform_now(id) }
  end

  class FixedSummary
    def initialize(result) = (@result = result)
    def call(_book) = @result
  end

  class RaisingService
    def call(_book) = raise("service should not be called")
  end

  private

  # ClaudeClient.new 을 configured?=true 로, BookSummaryService.new 을 주입 서비스로 임시 교체한다
  # (Minitest 6 은 minitest/mock 미제공 — sequel_feedback_job_test 의 stub_new 선례).
  def run_with_key(service)
    configured = Object.new
    def configured.configured? = true
    Ai::ClaudeClient.define_singleton_method(:new) { |*, **| configured }
    Ai::BookSummaryService.define_singleton_method(:new) { |*, **| service }
    yield
  ensure
    Ai::ClaudeClient.singleton_class.send(:remove_method, :new)
    Ai::BookSummaryService.singleton_class.send(:remove_method, :new)
  end
end
