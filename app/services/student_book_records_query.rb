# 이 책의 내 기록(내 서재 책 제목의 목적지) — 현재 학생이 책 한 권으로 한 활동을 모은 읽기 전용 조회.
# 독후감·게임 완료(퀴즈·나는 누구게?는 완료 여부만)·내가 쓴 뒷이야기·책 소개·토론 글·낸 문제.
#
# **정책 Scope(학급 경계)를 쓰지 않고 user_id 로 직접 좁힌다.** 뒷이야기·책 소개의 Scope 는 "같은 반
# 친구 글 목록"을 위한 학급 경계라, 학년이 올라 반이 바뀐 학생은 자기가 쓴 예전 글까지 볼 수 없게 된다.
# 여기서 보여 주는 것은 모두 본인이 쓴 글이므로 소유자 기준이 맞다.
class StudentBookRecordsQuery
  # 게임 종류(Games::BaseController::CATALOG 키)와 그 책으로 마지막에 한 날.
  GameCompletion = Data.define(:key, :last_played_on)

  # forum: 독서 토론(reading_discussion) 기능이 꺼진 학급이면 false — 토론 글을 조회하지 않는다.
  def initialize(user, book, forum: true)
    @user = user
    @book = book
    @forum = forum
  end

  def reports
    @reports ||= @user.reports.where(book: @book).includes(:book).order(created_at: :desc).to_a
  end

  # 게임 종류별 마지막 날짜, 카탈로그 순서. 퀴즈·나는 누구게?는 완료 원장(game_plays)으로 접고(옛 classic
  # 은 quiz 로 합친다), **책 소개·뒷이야기는 쓴 글이 있을 때만 완료다** — 체험 시드처럼 원장만 있고 글이
  # 없으면 "완료"라고 해 놓고 보여 줄 글이 없다. StudentLibraryQuery 의 게임 집계와 같은 기준.
  def game_completions
    @game_completions ||= begin
      written = StudentLibraryQuery::WRITTEN_GAMES.keys
      last_played = @user.game_plays.where(book: @book).where.not(game_type: written)
                         .group(:game_type).maximum(:played_on)
      classic = last_played.delete("classic")
      last_played["quiz"] = [ last_played["quiz"], classic ].compact.max if classic
      { "book" => intros, "sequel" => sequels }.each do |key, writings|
        last_played[key] = writings.map { |w| w.created_at.to_date }.max if writings.any?
      end

      Games::BaseController::CATALOG.keys.filter_map do |key|
        GameCompletion.new(key: key, last_played_on: last_played[key]) if last_played[key]
      end
    end
  end

  def sequels
    # user 프리로드 — 코멘트 파셜이 AI 사용 고지(ai_assisted_for?(sequel.user))에 글쓴이를 읽는다.
    @sequels ||= BookSequel.where(user: @user, book: @book).includes(:user).order(created_at: :desc).to_a
  end

  def intros
    @intros ||= BookIntro.where(user: @user, book: @book).order(created_at: :desc).to_a
  end

  # 이 책 토론방에 쓴 보이는 글(숨김 글·숨김 토론방 제외 — ForumPost.visible_in_book_topics).
  def forum_posts
    return [] unless @forum

    @forum_posts ||= ForumPost.visible_in_book_topics
                              .where(user: @user, topics: { book_id: @book.id })
                              .includes(:topic).order(created_at: :desc).to_a
  end

  def contributions
    # 카드는 책 제목을 빼고 그리므로(show_book: false) 책을 다시 읽지 않는다. 정렬은 내가 낸 문제 목록과 같다.
    @contributions ||= @user.quiz_contributions.where(book: @book).order(created_at: :desc, id: :desc).to_a
  end

  def games?
    game_completions.any? || sequels.any? || intros.any?
  end

  def empty?
    reports.empty? && !games? && forum_posts.empty? && contributions.empty?
  end
end
