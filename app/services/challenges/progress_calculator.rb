module Challenges
  # 챌린지 목표 진행도 계산(챌린지 목표화 — Missions::ProgressCalculator 미러). 미션과 차이:
  #   - 경계: 미션은 학급(reports.classroom_id)으로 좁히지만, 챌린지는 전국/학교 스코프라 **뷰어 학생
  #     본인의 활동 전체**를 센다(스코프 적격 여부는 EvaluateProgress 가 후보를 좁힐 때 판단).
  #   - 기간: **참여 시점(participation.joined_at) ~ window_end**. 하한은 challenge.window_start
  #     (starts_on 또는 생성일)와 참여 시각 중 **늦은 쪽**이라 참여 전에 쓴 독후감·플레이한 게임은
  #     집계되지 않는다("챌린지 참여 후 활동만 인정"). participation 이 없으면(미참여) 전부 0 이다.
  # 목표별 지정 도서('여러 책' any-of): goal.books 가 있으면 그 목록 중 어느 책의 독후감/game_plays 든
  # `where(book_id: [...])` 로 합산하고, 비면 아무 책이나 집계한다.
  class ProgressCalculator
    ZONE = ActiveSupport::TimeZone["Asia/Seoul"]

    # participation 은 필수 키워드다 — 빠뜨리면 조용히 '전 기간 집계'로 되돌아가므로 호출부가
    # 참여 원장을 반드시 넘기게 강제한다(미참여는 nil 을 명시적으로 넘긴다).
    def initialize(challenge, user, participation:)
      @challenge = challenge
      @user = user
      @participation = participation
    end

    # { completed:, goals: [{ type:, current:, target:, met:, book_title: }] }
    def call
      rows = ordered_goals.map { |goal| goal_row(goal) }
      { completed: rows.any? && rows.all? { |row| row[:met] }, goals: rows }
    end

    # 모든 목표 충족 여부. 목표가 없으면 false(vacuous-true 오지급 방지 — Rewarder 도 별도 가드).
    def completed?
      goals = ordered_goals
      return false if goals.empty?

      goals.all? { |goal| current_for(goal) >= goal.target_count }
    end

    private

    def ordered_goals
      @ordered_goals ||= @challenge.challenge_goals.includes(:books).order(:position, :id).to_a
    end

    def goal_row(goal)
      current = current_for(goal)
      { type: goal.goal_type, current: current, target: goal.target_count,
        met: current >= goal.target_count, book_title: book_title_for(goal) }
    end

    # 지정 도서 표시용 제목(여러 책이면 " · " 로 이음, 없으면 nil). 뷰가 그대로 렌더.
    def book_title_for(goal)
      goal.books.map(&:title).join(" · ").presence
    end

    def current_for(goal)
      return 0 if @participation.nil? # 미참여 = 집계 대상 아님(참여하기 전 활동은 인정하지 않는다)

      case goal.goal_type
      when "approved_reports" then approved_reports_count(goal)
      when "game_plays" then game_plays_count(goal)
      else 0
      end
    end

    # 뷰어 본인의 승인 원본 독후감(고쳐쓰기 제외)을 기간 창 안에서 센다. 지정 도서(들)면 그 목록만.
    def approved_reports_count(goal)
      (@approved_reports_count ||= {})[goal.id] ||= begin
        book_ids = goal.books.map(&:id)
        scope = @user.reports.where(reviewed: true, revision_of_id: nil).where(created_at: window_range)
        scope = scope.where(book_id: book_ids) if book_ids.any?
        scope.count
      end
    end

    # 뷰어 본인의 게임 완료(game_plays)를 기간 창 안에서 센다. 지정 도서(들)면 그 목록만.
    # played_on 은 날짜 컬럼이라 하한도 날짜(참여일)로 clamp 한다 — 참여 당일에 먼저 플레이한
    # 게임까지 인정되는 근사이며, 미션의 assigned_on clamp 와 같은 관용구다.
    def game_plays_count(goal)
      (@game_plays_count ||= {})[goal.id] ||= begin
        book_ids = goal.books.map(&:id)
        start_d = [ @challenge.window_start, joined_on ].compact.max
        end_d   = @challenge.window_end
        scope = @user.game_plays
        scope = scope.where("played_on >= ?", start_d) if start_d
        scope = scope.where("played_on <= ?", end_d) if end_d
        scope = scope.where(book_id: book_ids) if book_ids.any?
        scope.count
      end
    end

    # 참여 시각(또는 창 시작 00:00 Asia/Seoul 중 늦은 쪽) ~ 종료일+1 00:00(상한 배타).
    # window_end 가 nil 이면 상한 없음. reports.created_at 은 datetime 이라 참여 '시각'까지 정밀 비교한다.
    def window_range
      e = @challenge.window_end
      lower = [ window_start_at, @participation&.joined_at ].compact.max
      upper = e ? (ZONE.local(e.year, e.month, e.day) + 1.day) : nil
      lower...upper
    end

    def window_start_at
      s = @challenge.window_start
      s && ZONE.local(s.year, s.month, s.day)
    end

    # 참여일(Asia/Seoul) — played_on(date) 비교용.
    def joined_on
      @participation&.joined_at&.in_time_zone(ZONE)&.to_date
    end
  end
end
