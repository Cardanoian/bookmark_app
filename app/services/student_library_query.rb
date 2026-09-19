# 내 서재(menu_refactor 심화 §2.D.4·§5.2) — 현재 학생의 **책별 활동 집계** 읽기 전용 조회.
# 저장한 책이 아니라 실제 활동한 책 기준 — 독후감(reports)·게임 완료(game_plays)·토론 글(forum_posts,
# 책이 걸린 토론방)·낸 문제(quiz_contributions). 전체 활동을 Ruby 로 group_by 하지 않고 book_id 기준
# GROUP BY 서브집계 후 Book 을 한 번에 로드한다. 책 미연결(book_id nil) 독후감은 정규화한 book_title 로
# 별도 레거시 그룹에 담는다(실제 Book 과 문자열만으로 자동 결합하지 않음).
class StudentLibraryQuery
  # 활동 종류 필터(화면 칩 순서). 게임 키는 게임 카탈로그가 단일 진실이다 — 게임이 늘면 필터·배지도 따라 는다.
  GAME_KINDS = Games::BaseController::CATALOG.keys.freeze
  KINDS = [ "reports", *GAME_KINDS, "forum", "contributions" ].freeze
  # 글을 써야 끝나는 게임(책 소개 대결·뒷이야기 이어쓰기). 완료 여부는 완료 원장이 아니라 쓴 글로 정한다.
  WRITTEN_GAMES = { "book" => BookIntro, "sequel" => BookSequel }.freeze

  Entry = Struct.new(:book, :report_total, :report_approved, :report_pending, :game_types,
                     :forum_count, :contribution_count, :last_activity_at, keyword_init: true) do
    def status
      report_pending.positive? ? :in_progress : :completed
    end
  end
  LegacyGroup = Struct.new(:title, :report_total, :report_approved, :last_activity_at, keyword_init: true)

  attr_reader :kind

  # kind: nil(전체) | KINDS 중 하나(활동 종류 필터). 모르는 값은 전체로 본다.
  # forum: 독서 토론(reading_discussion) 기능이 꺼진 학급이면 false — 토론 글을 집계하지 않는다.
  def initialize(user, kind: nil, forum: true)
    @user = user
    @kind = KINDS.include?(kind.to_s) ? kind.to_s : nil
    # 토론이 꺼진 학급에는 토론 칩이 없으므로, 저장해 둔 ?kind=forum 주소는 전체로 돌린다.
    @kind = nil if @kind == "forum" && !forum
    @forum = forum
  end

  def entries
    @entries ||= build_entries
  end

  # 책 미연결 독후감은 독후감이라 '전체'·'독후감' 필터에서만 보인다.
  def legacy_report_groups
    return [] unless @kind.nil? || @kind == "reports"

    @legacy_report_groups ||= build_legacy_groups
  end

  private

  def build_entries
    reports = report_stats_by_book
    games = game_stats_by_book
    forum = forum_stats_by_book
    contributions = contribution_stats_by_book

    book_ids = filter_book_ids(reports, games, forum, contributions)
    return [] if book_ids.empty?

    books = Book.where(id: book_ids).index_by(&:id)
    book_ids.filter_map do |book_id|
      book = books[book_id]
      next unless book

      report = reports[book_id] || {}
      last = [ report[:last_at], games[book_id]&.dig(:last_at),
               forum[book_id]&.dig(:last_at), contributions[book_id]&.dig(:last_at) ].compact.max
      Entry.new(
        book: book,
        report_total: report[:total].to_i,
        report_approved: report[:approved].to_i,
        report_pending: report[:total].to_i - report[:approved].to_i,
        game_types: games[book_id]&.dig(:types) || [],
        forum_count: forum[book_id]&.dig(:count).to_i,
        contribution_count: contributions[book_id]&.dig(:count).to_i,
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

  # { book_id => { types: [게임 키, …(카탈로그 순)], last_at: } }
  # 퀴즈·나는 누구게?는 완료 원장(game_plays)으로 센다(옛 classic 은 quiz 로 통합된 게임이라 퀴즈로).
  # **책 소개·뒷이야기는 쓴 글이 있을 때만 완료다**(WRITTEN_GAMES) — 실제 앱에서는 글을 올려야 원장이
  # 생기지만, 체험 시드는 원장만 숫자대로 만들어(DemoSeeder#seed_games) "뒷이야기 완료"인데 볼 글이 없는
  # 책이 생겼다. 쓴 글이 기록의 진실이므로 그 두 게임의 원장 행은 화면 집계에 쓰지 않는다
  # (StudentBookRecordsQuery#game_completions 와 같은 기준. 몬스터 지표[ReadingStats]는 원장을 그대로 센다).
  def game_stats_by_book
    stats = Hash.new { |hash, book_id| hash[book_id] = { types: [], last_at: nil } }
    add_game = lambda do |book_id, key, last_at|
      stat = stats[book_id]
      stat[:types] << key
      stat[:last_at] = [ stat[:last_at], last_at ].compact.max
    end

    @user.game_plays.where.not(book_id: nil).where.not(game_type: WRITTEN_GAMES.keys)
         .group(:book_id, :game_type).maximum(:played_on)
         .each { |(book_id, game_type), played_on| add_game.call(book_id, game_type == "classic" ? "quiz" : game_type, to_time(played_on)) }
    WRITTEN_GAMES.each do |key, model|
      model.where(user: @user).group(:book_id).maximum(:created_at)
           .each { |book_id, created_at| add_game.call(book_id, key, created_at) }
    end

    stats.each_value { |stat| stat[:types] = GAME_KINDS & stat[:types] }
    # 기본값 proc 을 떼어 낸다 — 남겨 두면 게임이 없는 책을 조회하는 것만으로 빈 항목이 생겨 게임 필터에 섞일 수 있다.
    stats.default_proc = nil
    stats
  end

  # { book_id => { count:, last_at: } } — 책이 걸린 토론방에 쓴 보이는 글(ForumPost.visible_in_book_topics).
  def forum_stats_by_book
    return {} unless @forum

    rows = ForumPost.visible_in_book_topics.where(user: @user)
                    .group("topics.book_id")
                    .pluck(Arel.sql("topics.book_id"), Arel.sql("COUNT(*)"), Arel.sql("MAX(forum_posts.created_at)"))
    datetime = ForumPost.type_for_attribute(:created_at)
    rows.to_h { |book_id, count, last_at| [ book_id, { count: count, last_at: datetime.deserialize(last_at) } ] }
  end

  # { book_id => { count:, last_at: } } — 이 책으로 낸 문제(검토 상태 무관).
  def contribution_stats_by_book
    rows = @user.quiz_contributions.group(:book_id)
                .pluck(:book_id, Arel.sql("COUNT(*)"), Arel.sql("MAX(created_at)"))
    datetime = QuizContribution.type_for_attribute(:created_at)
    rows.to_h { |book_id, count, last_at| [ book_id, { count: count, last_at: datetime.deserialize(last_at) } ] }
  end

  def filter_book_ids(reports, games, forum, contributions)
    case @kind
    when nil             then reports.keys | games.keys | forum.keys | contributions.keys
    when "reports"       then reports.keys
    when "forum"         then forum.keys
    when "contributions" then contributions.keys
    else games.select { |_book_id, stat| stat[:types].include?(@kind) }.keys
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

  # 게임 완료일(date)을 앱 시간대(Asia/Seoul) 자정으로 바꾼다. Date#to_time 은 서버 OS 시간대를 따라
  # 운영(UTC)에서만 09:00 KST 가 되어, 같은 날 쓴 다른 활동과의 순서가 환경마다 달라졌다.
  def to_time(value)
    return nil if value.blank?

    value.respond_to?(:in_time_zone) ? value.in_time_zone : value
  end
end
