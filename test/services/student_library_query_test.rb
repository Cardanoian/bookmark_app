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

  private

  def report(**attributes)
    Report.create!({ user: @student, classroom: @classroom }.merge(attributes))
  end
end
