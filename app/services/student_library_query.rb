# 내 서재(menu_refactor 심화 §2.D.4·§5.2) — 현재 학생의 **책별 활동 집계** 읽기 전용 조회.
# 저장한 책이 아니라 실제 활동한 책(reports·game_plays) 기준. 전체 활동을 Ruby 로 group_by 하지 않고
# book_id 기준 GROUP BY 서브집계 후 Book 을 한 번에 로드한다. 책 미연결(book_id nil) 독후감은
# 정규화한 book_title 로 별도 레거시 그룹에 담는다(실제 Book 과 문자열만으로 자동 결합하지 않음).
class StudentLibraryQuery
  Entry = Struct.new(:book, :report_total, :report_approved, :report_pending, :game_count, :last_activity_at, keyword_init: true) do
    def status
      report_pending.positive? ? :in_progress : :completed
    end
  end
  LegacyGroup = Struct.new(:title, :report_total, :report_approved, :last_activity_at, keyword_init: true)

  # kind: nil | :reports | :games (활동 종류 필터)
  def initialize(user, kind: nil)
    @user = user
    @kind = kind&.to_sym
  end

  def entries
    @entries ||= build_entries
  end

  def legacy_report_groups
    @legacy_report_groups ||= build_legacy_groups
  end

  private

  def build_entries
    reports = report_stats_by_book
    games = game_stats_by_book
    book_ids = (reports.keys | games.keys)
    book_ids = filter_book_ids(book_ids, reports, games)
    return [] if book_ids.empty?

    books = Book.where(id: book_ids).index_by(&:id)
    book_ids.filter_map do |book_id|
      book = books[book_id]
      next unless book

      report = reports[book_id] || {}
      last = [ report[:last_at], games[book_id]&.dig(:last_at) ].compact.max
      Entry.new(
        book: book,
        report_total: report[:total].to_i,
        report_approved: report[:approved].to_i,
        report_pending: report[:total].to_i - report[:approved].to_i,
        game_count: games[book_id]&.dig(:count).to_i,
        last_activity_at: last
      )
    end.sort_by { |e| [ e.last_activity_at || Time.at(0), e.book.id ] }.reverse
  end

  # { book_id => { total:, approved:, last_at: } }
  # last_at = 그 책 독후감의 마지막 활동 시각. 낸 글은 **제출 시각**, 아직 안 낸 초안은 처음 저장한 시각
  # (created_at)이다 — 자동 저장 이후 created_at 은 "처음 쓰기 시작한 시각"이라, 월요일에 쓰기 시작해
  # 수요일에 낸 책이 월요일 활동으로 보이지 않게 한다. 집계(MAX)는 SQLite 가 UTC 문자열로 돌려주므로
  # 속성 타입으로 캐스팅한다(String#to_time 은 서버 로컬 시간대로 읽어 날짜가 9시간 어긋난다).
  def report_stats_by_book
    rows = @user.reports.where.not(book_id: nil)
                .group(:book_id)
                .pluck(:book_id,
                       Arel.sql("COUNT(*)"),
                       Arel.sql("SUM(CASE WHEN reviewed THEN 1 ELSE 0 END)"),
                       Arel.sql("MAX(COALESCE(submitted_at, created_at))"))
    datetime = Report.type_for_attribute(:submitted_at)
    rows.to_h { |book_id, total, approved, last_at| [ book_id, { total: total, approved: approved.to_i, last_at: datetime.deserialize(last_at) } ] }
  end

  # { book_id => { count:, last_at: } }
  def game_stats_by_book
    rows = @user.game_plays.where.not(book_id: nil)
                .group(:book_id)
                .pluck(:book_id, Arel.sql("COUNT(*)"), Arel.sql("MAX(played_on)"))
    rows.to_h { |book_id, count, last_on| [ book_id, { count: count, last_at: to_time(last_on) } ] }
  end

  def filter_book_ids(book_ids, reports, games)
    case @kind
    when :reports then book_ids.select { |id| reports.key?(id) }
    when :games   then book_ids.select { |id| games.key?(id) }
    else book_ids
    end
  end

  # 책 미연결 독후감을 정규화 제목으로 그룹핑(레거시). 문자열만으로 실제 Book 과 합치지 않는다.
  # 마지막 활동 시각은 report_stats_by_book 과 같은 기준(제출 시각, 초안은 created_at).
  def build_legacy_groups
    rows = @user.reports.where(book_id: nil).where.not(book_title: [ nil, "" ])
                .pluck(:book_title, :reviewed, :submitted_at, :created_at)
    grouped = rows.group_by { |title, *| title.to_s.squish }
    grouped.filter_map do |title, entries|
      next if title.blank?

      LegacyGroup.new(
        title: title,
        report_total: entries.size,
        report_approved: entries.count { |_t, reviewed, *| reviewed },
        last_activity_at: entries.map { |_t, _r, submitted_at, created_at| submitted_at || created_at }.compact.max
      )
    end.sort_by { |g| g.last_activity_at || Time.at(0) }.reverse
  end

  def to_time(value)
    return nil if value.blank?

    value.respond_to?(:to_time) ? value.to_time : value
  end
end
