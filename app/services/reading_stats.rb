# 진화/뱃지 조건 판정용 독서 지표 집계(monsters.md §4 진화조건 키 사전).
# 모든 값은 "누적 도달 목표". #meets? 는 조건 해시의 모든 키를 AND 로 판정한다.
class ReadingStats
  # #meets? 에서 숫자 비교(>=)로 다루는 키. 진화(evolve_condition)·해금(unlock_condition) 공용
  # 화이트리스트(MonsterSpecies::ALLOWED_CONDITION_KEYS)의 단일 진실이다.
  NUMERIC_KEYS = %i[
    points reports max_daily_reports distinct_genres a_grades b_or_better classics revisions
    streak_days missions challenges quizzes topic_posts cheers_received dex_count
    game_plays distinct_games game_books
  ].freeze

  def initialize(user)
    @user = user
  end

  # 누적 트레이너 포인트.
  # NUMERIC_KEYS 지표는 모두 메모이즈한다(P2.2): ReadingStats 인스턴스는 요청/판정 단위로
  # 고정 유저 스냅샷을 읽으므로 캐싱이 안전하고, refresh_badges!(~13키)·도감(M몬스터×K조건)의
  # 반복 재쿼리를 없앤다. 모든 지표는 음이 아닌 정수(0 포함)를 반환하며 0 은 Ruby 에서 truthy 라
  # `||=` 재계산이 없다(nil/false 반환 지표가 없어 sentinel 불필요).
  def points
    @points ||= @user.points.to_i
  end

  # 승인된(검토 완료) 독후감 수.
  def reports
    @reports ||= approved_reports.count
  end

  # 하루 최다 독후감(역대 최댓값). 승인 독후감을 앱 시간대(Asia/Seoul) 제출일(created_at)별로
  # 묶어 그날의 **서로 다른 book_id 수**를 세고, 일자별 값의 최댓값을 취한다(monster_unlocks.md §일일 판정).
  # book_id 가 없는 독후감은 서로 다른 책으로 셀 수 없어 제외한다(distinct book 의미와 정합). 없으면 0.
  def max_daily_reports
    @max_daily_reports ||= begin
      pairs = approved_reports.where.not(book_id: nil).pluck(:created_at, :book_id)
      by_day = pairs.group_by { |created_at, _book_id| created_at.in_time_zone("Asia/Seoul").to_date }
      by_day.values.map { |rows| rows.map(&:last).uniq.size }.max || 0
    end
  end

  # 서로 다른 도서 카테고리 수(승인 독후감의 도서 기준).
  def distinct_genres
    @distinct_genres ||= Book.where(id: approved_reports.where.not(book_id: nil).select(:book_id))
                             .distinct.count(:category)
  end

  # A등급 첨삭 수(승인된 독후감 기준 — 다른 품질 지표와 일관, 승인 전 인플레이션 방지).
  def a_grades
    @a_grades ||= approved_reports.where(level: "A").count
  end

  # B등급 이상(A/B) 수(승인된 독후감 기준).
  def b_or_better
    @b_or_better ||= approved_reports.where(level: %w[A B]).count
  end

  # 완독한 고전 수 = 고전(category: classic) 카테고리의 **서로 다른 책**에 연결된 승인 독후감 수.
  # 진화(evolve_condition)·해금(unlock_condition) 공유 지표. 같은 고전을 여러 번 읽어도 1권으로만
  # 세어(distinct book_id) 반복 치팅을 막는다(monster_unlocks.md §2). 임계 2·3(turtle_2·dragon_2·dex08)이
  # 더 엄격해지지만 고전 카탈로그가 넉넉해 도달성 문제는 없다(회귀 골든 테스트로 고정).
  def classics
    @classics ||= approved_reports.joins(:book).merge(Book.classic).distinct.count(:book_id)
  end

  # 향상된 고쳐쓰기 수(improvement > 0, 승인된 독후감 기준).
  def revisions
    @revisions ||= approved_reports.where("improvement > 0").count
  end

  # 최장 연속 제출일(연속 독서 스트릭). 제출일(created_at) 기준 연속 달력일의 최대 길이.
  def streak_days
    @streak_days ||= begin
      dates = @user.reports.pluck(:created_at).compact.map(&:to_date).uniq.sort
      longest_consecutive_run(dates)
    end
  end

  # 참여 미션 수(mission_id distinct).
  def missions
    @missions ||= @user.reports.where.not(mission_id: nil).distinct.count(:mission_id)
  end

  # 참여 챌린지 수(challenge_id distinct).
  def challenges
    @challenges ||= @user.reports.where.not(challenge_id: nil).distinct.count(:challenge_id)
  end

  # 퀴즈/게임 플레이 수(P5.6). 학생의 quiz_attempts 누적(독서게임 → 진화 조건 quizzes: 연동).
  def quizzes
    @quizzes ||= @user.quiz_attempts.count
  end

  # 토론 글 수(작성한 forum_posts, P5.4).
  def topic_posts
    @topic_posts ||= @user.forum_posts.count
  end

  # 받은 응원 수 합계.
  def cheers_received
    @cheers_received ||= @user.reports.sum(:cheers_count)
  end

  # 보유 몬스터(라인) 수(user_monsters distinct dex_no).
  def dex_count
    @dex_count ||= @user.user_monsters.distinct.count(:dex_no)
  end

  # 유효 게임 완료 기록 누적 횟수(game_plays 원장, 3B). 원장은 학생·게임·(책)·일자 단위로 dedup 된다.
  def game_plays
    @game_plays ||= @user.game_plays.count
  end

  # 플레이한 서로 다른 게임 종류 수(distinct game_type, 최대 5). 3B.
  def distinct_games
    @distinct_games ||= @user.game_plays.distinct.count(:game_type)
  end

  # 유효 게임으로 만난 서로 다른 책 수(distinct non-null book_id). 책 미연결 플레이는 제외. 3B.
  def game_books
    @game_books ||= @user.game_plays.where.not(book_id: nil).distinct.count(:book_id)
  end

  # 특정 뱃지 보유 여부.
  def badge?(key)
    @user.badges.exists?(key: key.to_s)
  end

  # 숫자 지표 전체 해시.
  def to_h
    NUMERIC_KEYS.index_with { |key| public_send(key) }
  end

  # 조건 해시의 모든 키 충족 여부(AND). 숫자 키는 >=, badge 는 보유 여부.
  # 화이트리스트(NUMERIC_KEYS + badge) 밖의 키는 크래시 대신 미충족(false)으로 처리한다.
  # evolve_condition 은 관리자 자유 편집 JSON 이라, 오타 키가 public_send 에서 NoMethodError
  # 를 내면 학생 도감(monsters#index → evolvable?)이 500 나기 때문(P1.5).
  def meets?(condition)
    return false if condition.blank?

    condition.all? do |key, target|
      if key.to_s == "badge"
        badge?(target)
      elsif NUMERIC_KEYS.include?(key.to_s.to_sym)
        public_send(key) >= target.to_i
      else
        false
      end
    end
  end

  private

  def approved_reports
    @user.reports.where(reviewed: true)
  end

  def longest_consecutive_run(dates)
    return 0 if dates.empty?

    best = 1
    current = 1
    dates.each_cons(2) do |previous, following|
      if following == previous + 1
        current += 1
        best = [ best, current ].max
      else
        current = 1
      end
    end
    best
  end
end
