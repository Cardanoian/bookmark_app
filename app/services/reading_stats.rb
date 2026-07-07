# 진화/뱃지 조건 판정용 독서 지표 집계(monsters.md §4 진화조건 키 사전).
# 모든 값은 "누적 도달 목표". #meets? 는 조건 해시의 모든 키를 AND 로 판정한다.
class ReadingStats
  # #meets? 에서 숫자 비교(>=)로 다루는 키.
  NUMERIC_KEYS = %i[
    points reports distinct_genres a_grades b_or_better classics revisions
    streak_days missions challenges quizzes topic_posts cheers_received dex_count
  ].freeze

  def initialize(user)
    @user = user
  end

  # 누적 트레이너 포인트.
  def points
    @user.points.to_i
  end

  # 승인된(검토 완료) 독후감 수.
  def reports
    approved_reports.count
  end

  # 서로 다른 도서 카테고리 수(승인 독후감의 도서 기준).
  def distinct_genres
    Book.where(id: approved_reports.where.not(book_id: nil).select(:book_id))
        .distinct.count(:category)
  end

  # A등급 첨삭 수(승인된 독후감 기준 — 다른 품질 지표와 일관, 승인 전 인플레이션 방지).
  def a_grades
    approved_reports.where(level: "A").count
  end

  # B등급 이상(A/B) 수(승인된 독후감 기준).
  def b_or_better
    approved_reports.where(level: %w[A B]).count
  end

  # 완독한 고전 수(category: classic 연동 승인 독후감).
  def classics
    approved_reports.joins(:book).merge(Book.classic).count
  end

  # 향상된 고쳐쓰기 수(improvement > 0, 승인된 독후감 기준).
  def revisions
    approved_reports.where("improvement > 0").count
  end

  # 최장 연속 제출일(마라톤 스트릭). 제출일(created_at) 기준 연속 달력일의 최대 길이.
  def streak_days
    dates = @user.reports.pluck(:created_at).compact.map(&:to_date).uniq.sort
    longest_consecutive_run(dates)
  end

  # 참여 미션 수(mission_id distinct).
  def missions
    @user.reports.where.not(mission_id: nil).distinct.count(:mission_id)
  end

  # 참여 챌린지 수(challenge_id distinct).
  def challenges
    @user.reports.where.not(challenge_id: nil).distinct.count(:challenge_id)
  end

  # 퀴즈/게임 플레이 수(P5.6). 학생의 quiz_attempts 누적(독서게임 → 진화 조건 quizzes: 연동).
  def quizzes
    @user.quiz_attempts.count
  end

  # 토론 글 수(작성한 forum_posts, P5.4).
  def topic_posts
    @user.forum_posts.count
  end

  # 받은 응원 수 합계.
  def cheers_received
    @user.reports.sum(:cheers_count)
  end

  # 보유 몬스터(라인) 수(user_monsters distinct dex_no).
  def dex_count
    @user.user_monsters.distinct.count(:dex_no)
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
  def meets?(condition)
    return false if condition.blank?

    condition.all? do |key, target|
      if key.to_s == "badge"
        badge?(target)
      else
        public_send(key) >= target.to_i
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
