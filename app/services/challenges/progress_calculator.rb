module Challenges
  # 챌린지 목표 진행도 계산(챌린지 목표화 — Missions::ProgressCalculator 미러). 미션과 차이:
  #   - 경계: 미션은 학급(reports.classroom_id)으로 좁히지만, 챌린지는 전국/학교 스코프라 **뷰어 학생
  #     본인의 활동 전체**를 센다(스코프 적격 여부는 EvaluateProgress 가 후보를 좁힐 때 판단).
  #   - 기간: challenge.window_start(starts_on 또는 생성일) ~ window_end(ends_on, nil=상한없음).
  # 목표별 지정 도서('여러 책' any-of): goal.books 가 있으면 그 목록 중 어느 책의 독후감/game_plays 든
  # `where(book_id: [...])` 로 합산하고, 비면 아무 책이나 집계한다.
  class ProgressCalculator
    ZONE = ActiveSupport::TimeZone["Asia/Seoul"]

    def initialize(challenge, user)
      @challenge = challenge
      @user = user
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
    def game_plays_count(goal)
      (@game_plays_count ||= {})[goal.id] ||= begin
        book_ids = goal.books.map(&:id)
        start_d = @challenge.window_start
        end_d   = @challenge.window_end
        scope = @user.game_plays
        scope = scope.where("played_on >= ?", start_d) if start_d
        scope = scope.where("played_on <= ?", end_d) if end_d
        scope = scope.where(book_id: book_ids) if book_ids.any?
        scope.count
      end
    end

    # 시작일 00:00(Asia/Seoul) ~ 종료일+1 00:00(상한 배타). window_end 가 nil 이면 상한 없음.
    def window_range
      s = @challenge.window_start
      e = @challenge.window_end
      lower = ZONE.local(s.year, s.month, s.day)
      upper = e ? (ZONE.local(e.year, e.month, e.day) + 1.day) : nil
      lower...upper
    end
  end
end
