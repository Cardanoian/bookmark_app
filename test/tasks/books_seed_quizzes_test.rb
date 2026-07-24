require "test_helper"
require "rake"
require "tempfile"
require "yaml"

# books:seed_quizzes 검증(Stage 2 큐레이션 문항 로더). 소형 임시 YAML(ENV["BOOK_QUIZZES_YML"] 주입)로
# 무네트워크·멱등·미매칭 skip·최초 도입 시 기존 system Quiz 은퇴·재실행 시 은퇴 스킵을 검증한다.
class BooksSeedQuizzesTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("books:seed_quizzes")
    @yml = Tempfile.new([ "book_quizzes", ".yml" ])
    ENV["BOOK_QUIZZES_YML"] = @yml.path
  end

  teardown do
    ENV.delete("BOOK_QUIZZES_YML")
    @yml&.close!
  end

  def write_yaml(hash)
    File.write(@yml.path, YAML.dump(hash))
  end

  def seed_quizzes!
    Rake::Task["books:seed_quizzes"].reenable
    capture_io { Rake::Task["books:seed_quizzes"].invoke }
  end

  def entry(title: "책")
    {
      "title" => title,
      "mcq" => [ { "prompt" => "주인공은?", "choices" => %w[가 나 다 라], "answer_index" => 0, "explanation" => "해설", "difficulty" => 1 } ],
      "hint_reveal" => [ { "answer" => "잎싹", "hints" => [ "동물", "두 글자" ], "explanation" => "", "difficulty" => 1 } ]
    }
  end

  # ── 매칭 도서에 축별 CuratedQuiz 생성 ──
  test "creates a CuratedQuiz per axis for a matching book" do
    isbn = TestBookIsbn.next
    book = Book.create!(title: "책1", isbn: isbn, category: :classic)
    write_yaml(isbn => entry(title: "책1"))

    out, = seed_quizzes!

    axes = CuratedQuiz.where(book_id: book.id).pluck(:content_axis).sort
    assert_equal %w[hint_reveal mcq], axes
    assert_equal %w[가 나 다 라], CuratedQuiz.find_by(book_id: book.id, content_axis: :mcq).payload.first["choices"]
    assert_match(/applied=2/, out)
  end

  # ── 멱등: 재실행이 새 행을 만들지 않고 payload 를 같은 값으로 수렴 ──
  test "is idempotent across re-runs" do
    isbn = TestBookIsbn.next
    book = Book.create!(title: "책2", isbn: isbn, category: :classic)
    write_yaml(isbn => entry)

    seed_quizzes!
    assert_equal 2, CuratedQuiz.where(book_id: book.id).count
    assert_nothing_raised { seed_quizzes! }
    assert_equal 2, CuratedQuiz.where(book_id: book.id).count, "재실행이 중복 행을 만들지 않는다"
  end

  # ── ISBN 미매칭 skip ──
  test "skips entries whose ISBN matches no book" do
    isbn = TestBookIsbn.next # 도서 미생성
    write_yaml(isbn => entry)

    out, = seed_quizzes!

    assert_match(/skipped_no_match=1/, out)
    assert_equal 0, CuratedQuiz.count
  end

  # ── 최초 도입: 기존 origin=system Quiz 은퇴 ──
  test "retires existing system quizzes on first curation introduction" do
    isbn = TestBookIsbn.next
    book = Book.create!(title: "책3", isbn: isbn, category: :classic)
    legacy = Quiz.create!(title: "온디맨드 mcq", created_by: Games::ContentProvider.system_user, book: book,
                          scope: :global, published: true, origin: :system, content_axis: :mcq, band: :g56,
                          content_version: 1, generation_status: :ready)
    teacher_quiz = Quiz.create!(title: "교사 퀴즈", created_by: Games::ContentProvider.system_user, book: book,
                                scope: :global, published: true, origin: :teacher, content_axis: :mcq, band: :g56,
                                content_version: 1, generation_status: :ready)
    write_yaml(isbn => entry(title: "책3"))

    out, = seed_quizzes!

    assert_not Quiz.exists?(legacy.id), "제네릭 system 캐시는 은퇴(삭제)된다"
    assert Quiz.exists?(teacher_quiz.id), "teacher origin 퀴즈는 은퇴 대상 아님"
    assert_match(/retired_books=1/, out)
  end

  # ── 재실행 시 은퇴 스킵(이미 큐레이션 도입된 책은 attempt 보존) ──
  test "skips retirement on re-run for an already-curated book" do
    isbn = TestBookIsbn.next
    book = Book.create!(title: "책4", isbn: isbn, category: :classic)
    write_yaml(isbn => entry(title: "책4"))

    seed_quizzes! # 최초 도입(은퇴할 system Quiz 없음)

    # 재실행 전에 새로운 system Quiz(예: 그 사이 플레이로 물질화된 캐시)를 심는다.
    materialized = Quiz.create!(title: "온디맨드 mcq", created_by: Games::ContentProvider.system_user, book: book,
                               scope: :global, published: true, origin: :system, content_axis: :mcq, band: :g56,
                               content_version: 1, generation_status: :ready)

    out, = seed_quizzes! # 재실행 — had=true 라 은퇴 스킵

    assert Quiz.exists?(materialized.id), "이미 큐레이션 도입된 책은 재실행 시 은퇴하지 않는다"
    assert_match(/retired_books=0/, out)
  end

  # ── 빈/무 YAML: 0건, 크래시 0 ──
  test "loads nothing from an empty YAML file without crashing" do
    File.write(@yml.path, "")
    assert_nothing_raised do
      out, = seed_quizzes!
      assert_match(/nothing to load/, out)
    end
  end

  test "is a no-op when the YAML file is missing" do
    ENV["BOOK_QUIZZES_YML"] = "/tmp/does-not-exist-#{SecureRandom.hex(4)}.yml"
    assert_nothing_raised do
      out, = seed_quizzes!
      assert_match(/nothing to load/, out)
    end
  end

  # ── 무네트워크: 스텁 없이도 크래시 0 ──
  test "makes no network calls (offline)" do
    isbn = TestBookIsbn.next
    Book.create!(title: "책5", isbn: isbn, category: :classic)
    write_yaml(isbn => entry(title: "책5"))
    assert_nothing_raised { seed_quizzes! }
  end
end
