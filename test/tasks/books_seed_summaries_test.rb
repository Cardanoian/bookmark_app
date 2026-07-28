require "test_helper"
require "rake"
require "tempfile"
require "yaml"

# books:seed_summaries + books:export_summaries 검증(Claude 줄거리 YAML 시드 인프라).
# 소형 임시 YAML(ENV["BOOK_SUMMARIES_YML"] 주입)으로 무네트워크·멱등·매칭/미매칭·빈파일 크래시 0 을,
# export 는 Claude 생성분(checked_at present)만 나가고 네이버 blurb(checked_at nil)는 제외됨을 검증한다.
class BooksSeedSummariesTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("books:seed_summaries")
    @yml = Tempfile.new([ "book_summaries", ".yml" ])
    ENV["BOOK_SUMMARIES_YML"] = @yml.path
  end

  teardown do
    ENV.delete("BOOK_SUMMARIES_YML")
    @yml&.close!
  end

  def write_yaml(hash)
    File.write(@yml.path, YAML.dump(hash))
  end

  def seed_summaries!
    Rake::Task["books:seed_summaries"].reenable
    capture_io { Rake::Task["books:seed_summaries"].invoke }
  end

  def export_summaries!
    Rake::Task["books:export_summaries"].reenable
    capture_io { Rake::Task["books:export_summaries"].invoke }
  end

  # ── seed_summaries: 매칭 도서(요약 blank)에 summary + checked_at 주입 ──
  test "injects summary and stamps checked_at on a matching book with a blank summary" do
    isbn = TestBookIsbn.next
    book = Book.create!(title: "책1", isbn: isbn, category: :classic)
    write_yaml(isbn => { "title" => "책1", "summary" => "저장된 줄거리예요." })

    seed_summaries!

    book.reload
    assert_equal "저장된 줄거리예요.", book.summary
    assert_not_nil book.summary_checked_at, "게이트가 확인·앎으로 인식하도록 checked_at 을 함께 세팅한다"
  end

  # ── 이미 summary 있는 책은 불변(멱등·기존 요약 보존) ──
  test "leaves a book that already has a summary unchanged" do
    isbn = TestBookIsbn.next
    book = Book.create!(title: "책2", isbn: isbn, category: :classic, summary: "기존 요약")
    write_yaml(isbn => { "title" => "책2", "summary" => "YAML 요약" })

    out, = seed_summaries!

    assert_equal "기존 요약", book.reload.summary
    assert_match(/skipped_present=1/, out)
  end

  # ── 재실행 멱등: 두 번째 실행이 이미 채워진 책을 다시 쓰지 않는다 ──
  test "is idempotent across re-runs" do
    isbn = TestBookIsbn.next
    book = Book.create!(title: "책3", isbn: isbn, category: :classic)
    write_yaml(isbn => { "title" => "책3", "summary" => "저장 요약" })

    seed_summaries!
    first_checked_at = book.reload.summary_checked_at
    seed_summaries!

    assert_equal "저장 요약", book.reload.summary
    assert_equal first_checked_at, book.reload.summary_checked_at, "이미 채워진 책은 재적재 시 다시 쓰지 않는다"
  end

  # ── ISBN 매칭 안 되는 항목은 skip(로그) ──
  test "skips YAML entries whose ISBN matches no book" do
    isbn = TestBookIsbn.next # 도서 미생성 → 매칭 없음
    write_yaml(isbn => { "title" => "없는책", "summary" => "요약" })

    out, = seed_summaries!

    assert_match(/skipped_no_match=1/, out)
    assert_match(/applied=0/, out)
  end

  # ── 빈 YAML: 0건 처리, 크래시 0 ──
  test "loads nothing from an empty YAML file without crashing" do
    File.write(@yml.path, "")

    assert_nothing_raised do
      out, = seed_summaries!
      assert_match(/nothing to load/, out)
    end
  end

  # ── YAML 파일 없음: no-op, 크래시 0 ──
  test "is a no-op when the YAML file is missing" do
    ENV["BOOK_SUMMARIES_YML"] = "/tmp/does-not-exist-#{SecureRandom.hex(4)}.yml"

    assert_nothing_raised do
      out, = seed_summaries!
      assert_match(/nothing to load/, out)
    end
  end

  # ── 무네트워크: 스텁 없이도(test_helper 가 Claude 키 공란 강제) 크래시 0 ──
  test "makes no network calls (offline)" do
    isbn = TestBookIsbn.next
    Book.create!(title: "책4", isbn: isbn, category: :classic)
    write_yaml(isbn => { "title" => "책4", "summary" => "요약" })

    assert_nothing_raised { seed_summaries! }
  end

  # ── export: Claude 생성분(checked_at present)만 나가고 네이버 blurb(checked_at nil)는 제외 ──
  test "export writes only Claude-generated summaries, excluding naver blurbs" do
    claude_isbn = TestBookIsbn.next
    naver_isbn = TestBookIsbn.next
    Book.create!(title: "제미나이책", isbn: claude_isbn, category: :classic,
                 summary: "제미나이 줄거리", summary_checked_at: Time.current)
    Book.create!(title: "네이버책", isbn: naver_isbn, category: :recommended,
                 summary: "네이버 블러브") # summary 있음·checked_at nil

    export_summaries!

    data = YAML.safe_load_file(@yml.path, aliases: false)
    assert data.key?(claude_isbn), "Claude 생성분(checked_at present)은 export 된다"
    assert_equal "제미나이 줄거리", data[claude_isbn]["summary"]
    assert_not data.key?(naver_isbn), "네이버 blurb(checked_at nil)는 제외된다"
  end
end
