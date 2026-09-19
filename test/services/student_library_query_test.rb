require "test_helper"

# 내 서재(StudentLibraryQuery) — 책별 활동의 "최근 활동" 시각과 그 순서.
#
# 자동 저장(2026-09-12)은 첫 저장에서 초안 행을 만든다. 그래서 created_at 은 "쓰기 시작한 시각"이고,
# 낸 글의 최근 활동은 **제출 시각**, 아직 안 낸 초안은 처음 저장한 시각(created_at)이다.
class StudentLibraryQueryTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "서재초등학교")
    @classroom = Classroom.create!(school: @school, grade: 4, class_no: 1)
    @student = User.create!(school: @school, classroom: @classroom, name: "서재학생", password: "password")
  end

  test "a submitted report's last activity is its submission time (in KST)" do
    book = Book.create!(title: "월요일에 시작한 책", category: :recommended)
    submitted_at = Time.zone.local(2026, 9, 9, 8, 30) # KST 수요일 아침 — UTC 로는 전날
    report(book: book, created_at: submitted_at - 2.days, submitted_at: submitted_at)

    entry = StudentLibraryQuery.new(@student).entries.sole
    assert_equal submitted_at, entry.last_activity_at
    # SQLite 집계(MAX)는 UTC 문자열이라 서버 시간대로 읽으면 날짜가 어긋난다. 화면 날짜도 낸 날이어야 한다.
    assert_equal Date.new(2026, 9, 9), entry.last_activity_at.to_date
  end

  test "an unsubmitted draft counts from when it was first saved" do
    book = Book.create!(title: "쓰는 중인 책", category: :recommended)
    started = Time.zone.local(2026, 9, 10, 9)
    report(book: book, created_at: started)

    entry = StudentLibraryQuery.new(@student).entries.sole
    assert_equal started, entry.last_activity_at
    assert_equal :in_progress, entry.status
  end

  test "books are ordered by the latest submission, not by when writing started" do
    started_first = Book.create!(title: "먼저 시작해 나중에 낸 책", category: :recommended)
    started_later = Book.create!(title: "나중에 시작해 먼저 낸 책", category: :recommended)
    report(book: started_first, created_at: Time.zone.local(2026, 9, 1, 10), submitted_at: Time.zone.local(2026, 9, 5, 10))
    report(book: started_later, created_at: Time.zone.local(2026, 9, 2, 10), submitted_at: Time.zone.local(2026, 9, 3, 10))

    assert_equal [ started_first, started_later ], StudentLibraryQuery.new(@student).entries.map(&:book)
  end

  test "legacy title-only groups use the same submission-time rule" do
    report(book_title: "제목만 쓴 책", created_at: Time.zone.local(2026, 9, 1, 10), submitted_at: Time.zone.local(2026, 9, 4, 10))

    group = StudentLibraryQuery.new(@student).legacy_report_groups.sole
    assert_equal Time.zone.local(2026, 9, 4, 10), group.last_activity_at
  end

  # ── 활동 종류별 필터 ─────────────────────────────────────────────────────
  test "every activity kind puts its book on the shelf and each filter picks only its own books" do
    books = %w[독후감 퀴즈 나는누구게 책소개 뒷이야기 토론 출제].index_with { |name| Book.create!(title: "#{name}책", category: :recommended) }
    report(book: books["독후감"])
    { "퀴즈" => :quiz, "나는누구게" => :whoami }.each do |name, game_type|
      @student.game_plays.create!(game_type: game_type, book: books[name], played_on: Date.current)
    end
    # 책 소개·뒷이야기는 실제 앱처럼 글과 완료 원장을 함께 만든다(완료 여부는 글로 정한다).
    BookIntro.create!(user: @student, book: books["책소개"], classroom: @classroom, body: "이 책을 친구에게 소개해요.")
    BookSequel.create!(user: @student, book: books["뒷이야기"], classroom: @classroom, body: "책이 끝난 뒤의 이야기예요.")
    @student.game_plays.create!(game_type: :book, book: books["책소개"], played_on: Date.current)
    @student.game_plays.create!(game_type: :sequel, book: books["뒷이야기"], played_on: Date.current)
    topic = Topic.create!(scope: :classroom, classroom: @classroom, book: books["토론"], title: "책 토론")
    ForumPost.create!(topic: topic, user: @student, text: "토론 글이에요")
    QuizContribution.create!(user: @student, book: books["출제"], classroom: @classroom, content_axis: :mcq, band: :g34,
                             payload: { "prompt" => "질문?", "choices" => %w[가 나 다 라], "answer_index" => 0, "explanation" => "" })

    assert_equal books.values.map(&:id).sort, StudentLibraryQuery.new(@student).entries.map { |e| e.book.id }.sort

    expected = { "reports" => "독후감", "quiz" => "퀴즈", "whoami" => "나는누구게", "book" => "책소개",
                 "sequel" => "뒷이야기", "forum" => "토론", "contributions" => "출제" }
    expected.each do |kind, name|
      assert_equal [ books[name] ], StudentLibraryQuery.new(@student, kind: kind).entries.map(&:book), "kind=#{kind}"
    end
  end

  test "an entry carries its game kinds in catalog order, counting old classic plays as the quiz" do
    book = Book.create!(title: "여러 게임 책", category: :recommended)
    BookSequel.create!(user: @student, book: book, classroom: @classroom, body: "책이 끝난 뒤의 이야기예요.")
    @student.game_plays.create!(game_type: :classic, book: book, played_on: Date.current - 3)

    entry = StudentLibraryQuery.new(@student).entries.sole
    assert_equal %w[quiz sequel], entry.game_types
    assert_equal [ book ], StudentLibraryQuery.new(@student, kind: "quiz").entries.map(&:book)
  end

  # 시드 데이터처럼 뒷이야기·책 소개 글만 있고 게임 완료 원장이 없어도 그 게임을 한 책으로 센다.
  test "a written sequel or intro counts as that game even without a game_play row" do
    sequel_book = Book.create!(title: "글만 있는 뒷이야기 책", category: :recommended)
    intro_book = Book.create!(title: "글만 있는 책 소개 책", category: :recommended)
    BookSequel.create!(user: @student, book: sequel_book, classroom: @classroom, body: "책이 끝난 뒤의 이야기예요.")
    BookIntro.create!(user: @student, book: intro_book, classroom: @classroom, body: "이 책을 친구에게 소개해요.")

    assert_equal [ sequel_book ], StudentLibraryQuery.new(@student, kind: "sequel").entries.map(&:book)
    assert_equal [ intro_book ], StudentLibraryQuery.new(@student, kind: "book").entries.map(&:book)
    assert_equal %w[sequel], StudentBookRecordsQuery.new(@student, sequel_book).game_completions.map(&:key)
  end

  # 체험 시드(DemoSeeder#seed_games)는 글 없이 완료 원장만 숫자대로 만든다. 책 소개·뒷이야기는 쓴 글이
  # 기록이라, 글 없는 원장만으로는 "완료"라고 하지 않는다(보여 줄 글이 없는 완료가 생겼다 — 운영 체험
  # 이도현 학생의 『검피 아저씨의 뱃놀이』).
  test "book or sequel game plays without a written entry are not shown as completed" do
    book = Book.create!(title: "원장만 있는 책", category: :recommended)
    @student.game_plays.create!(game_type: :sequel, book: book, played_on: Date.current)
    @student.game_plays.create!(game_type: :book, book: book, played_on: Date.current)

    assert_empty StudentLibraryQuery.new(@student).entries
    assert_empty StudentLibraryQuery.new(@student, kind: "sequel").entries
    assert_empty StudentBookRecordsQuery.new(@student, book).game_completions

    @student.game_plays.create!(game_type: :whoami, book: book, played_on: Date.current)
    assert_equal %w[whoami], StudentLibraryQuery.new(@student).entries.sole.game_types
    assert_equal %w[whoami], StudentBookRecordsQuery.new(@student, book).game_completions.map(&:key)
  end

  test "hidden forum posts and discussion-off classrooms do not put a book on the shelf" do
    book = Book.create!(title: "숨긴 토론 책", category: :recommended)
    topic = Topic.create!(scope: :classroom, classroom: @classroom, book: book, title: "토론")
    ForumPost.create!(topic: topic, user: @student, text: "숨긴 글", hidden: true)
    assert_empty StudentLibraryQuery.new(@student).entries

    ForumPost.create!(topic: topic, user: @student, text: "보이는 글")
    assert_equal 1, StudentLibraryQuery.new(@student).entries.sole.forum_count
    assert_empty StudentLibraryQuery.new(@student, forum: false).entries
  end

  test "posts in a hidden topic count nowhere, and a forum filter falls back to all when discussion is off" do
    book = Book.create!(title: "숨긴 토론방 책", category: :recommended)
    topic = Topic.create!(scope: :classroom, classroom: @classroom, book: book, title: "숨긴 토론방", hidden: true)
    ForumPost.create!(topic: topic, user: @student, text: "보이는 글이지만 토론방이 숨김")

    assert_empty StudentLibraryQuery.new(@student).entries
    assert_empty StudentBookRecordsQuery.new(@student, book).forum_posts
    assert_nil StudentLibraryQuery.new(@student, kind: "forum", forum: false).kind
    assert_equal "forum", StudentLibraryQuery.new(@student, kind: "forum").kind
  end

  # 게임 완료일은 날짜뿐이라 앱 시간대(KST) 자정으로 잰다 — 서버 OS 시간대(운영 UTC)를 따르면 09:00 이 됐다.
  test "a game's last activity is midnight of its play date in the app time zone" do
    book = Book.create!(title: "게임한 책", category: :recommended)
    @student.game_plays.create!(game_type: :quiz, book: book, played_on: Date.new(2026, 9, 19))

    assert_equal Time.zone.local(2026, 9, 19), StudentLibraryQuery.new(@student).entries.sole.last_activity_at
  end

  test "the book records page folds old classic plays into the quiz chip" do
    book = Book.create!(title: "고전 읽기 책", category: :recommended)
    @student.game_plays.create!(game_type: :classic, book: book, played_on: Date.new(2026, 9, 1))
    @student.game_plays.create!(game_type: :quiz, book: book, played_on: Date.new(2026, 8, 1))

    completions = StudentBookRecordsQuery.new(@student, book).game_completions
    assert_equal %w[quiz], completions.map(&:key)
    assert_equal Date.new(2026, 9, 1), completions.sole.last_played_on
  end

  test "unknown kinds fall back to all, and legacy title-only groups show only for all and reports" do
    report(book_title: "제목만 쓴 책")

    assert_nil StudentLibraryQuery.new(@student, kind: "games").kind
    assert_equal 1, StudentLibraryQuery.new(@student).legacy_report_groups.size
    assert_equal 1, StudentLibraryQuery.new(@student, kind: "reports").legacy_report_groups.size
    assert_empty StudentLibraryQuery.new(@student, kind: "quiz").legacy_report_groups
  end

  private

  def report(**attributes)
    Report.create!({ user: @student, classroom: @classroom }.merge(attributes))
  end
end
