module Missions
  # 미션 목표 진행도 계산(menu_refactor 심화 §2.A.2). 두 경로:
  #   - 단건(authoritative): #call/#completed? — 보상 판정의 단일 진실. game_plays 목표는
  #     participation 기간으로 Asia/Seoul 날짜 clamp(전학 경계).
  #   - batch(표시용): .batch — 교사 현황 화면의 N+1 제거. GROUP BY 로 학생 다수를 한 번에 집계하되
  #     game clamp 는 근사(전학 드묾 전제, 보상 판정은 항상 단건 경로).
  #
  # 목표 인정 규칙(§8.7):
  #   approved_reports = reports.classroom_id(불변 스탬프) == mission.classroom_id + reviewed +
  #     원본(revision_of_id nil) + created_at 한국날짜가 기간 내. 멤버십은 스탬프가 보증하므로
  #     participation 기간 clamp 불필요(전학 후에도 그 학급 report 는 인정 — count==trigger parity).
  #   game_plays = game_plays.played_on 이 기간 ∩ participation 배정기간 내(스탬프 없어 clamp 필수).
  class ProgressCalculator
    ZONE = ActiveSupport::TimeZone["Asia/Seoul"]

    def initialize(mission, user, participation: nil)
      @mission = mission
      @user = user
      @participation = participation
    end

    # { completed:, goals: [{ type:, current:, target:, met: }] }
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

    # 교사 현황용 batch. participations(같은 mission) → { user_id => { completed:, goals: [...] } }.
    # 특정 도서 목표(goal.books)면 그 허용목록의 책 활동만 집계한다(any-of, goal_type 당 1개라 종류별 단건 필터).
    def self.batch(mission, participations:)
      user_ids = participations.map(&:user_id).uniq
      goals = mission.mission_goals.includes(:books).order(:position, :id).to_a
      return user_ids.index_with { { completed: false, goals: [] } } if goals.empty? || user_ids.empty?

      report_goal = goals.find(&:approved_reports?)
      game_goal = goals.find(&:game_plays?)
      report_book_ids = report_goal ? report_goal.books.map(&:id) : []
      game_book_ids   = game_goal ? game_goal.books.map(&:id) : []

      report_scope = Report.where(classroom_id: mission.classroom_id, reviewed: true, revision_of_id: nil,
                                  user_id: user_ids, created_at: window_range(mission))
      report_scope = report_scope.where(book_id: report_book_ids) if report_book_ids.any?
      report_counts = report_scope.group(:user_id).count

      game_scope = GamePlay.where(user_id: user_ids, played_on: mission.start_date..mission.end_date)
      game_scope = game_scope.where(book_id: game_book_ids) if game_book_ids.any?
      game_counts = game_scope.group(:user_id).count # (표시용 근사 — 전학 clamp 미적용)

      participations.each_with_object({}) do |participation, acc|
        rows = goals.map do |goal|
          current = case goal.goal_type
          when "approved_reports" then report_counts[participation.user_id].to_i
          when "game_plays" then game_counts[participation.user_id].to_i
          else 0
          end
          { type: goal.goal_type, current: current, target: goal.target_count,
            met: current >= goal.target_count, book_title: goal.books.map(&:title).join(" · ").presence }
        end
        acc[participation.user_id] = { completed: rows.all? { |row| row[:met] }, goals: rows }
      end
    end

    # 시작일 00:00(Asia/Seoul) ~ (종료일+1) 00:00, 상한 배타. reports.created_at(datetime) 경계.
    def self.window_range(mission)
      s = mission.start_date
      e = mission.end_date
      ZONE.local(s.year, s.month, s.day)...(ZONE.local(e.year, e.month, e.day) + 1.day)
    end

    private

    def ordered_goals
      @ordered_goals ||= @mission.mission_goals.includes(:books).order(:position, :id).to_a
    end

    def goal_row(goal)
      current = current_for(goal)
      { type: goal.goal_type, current: current, target: goal.target_count,
        met: current >= goal.target_count, book_title: goal.books.map(&:title).join(" · ").presence }
    end

    def current_for(goal)
      case goal.goal_type
      when "approved_reports" then approved_reports_count(goal)
      when "game_plays" then game_plays_count(goal)
      else 0
      end
    end

    # goal.id 별 메모 — 특정 도서(들) 지정이면 그 허용목록의 책 독후감만 센다(any-of, 비면 아무 책이나).
    def approved_reports_count(goal)
      (@approved_reports_count ||= {})[goal.id] ||= begin
        book_ids = goal.books.map(&:id)
        scope = @user.reports
          .where(classroom_id: @mission.classroom_id, reviewed: true, revision_of_id: nil)
          .where(created_at: self.class.window_range(@mission))
        scope = scope.where(book_id: book_ids) if book_ids.any?
        scope.count
      end
    end

    def game_plays_count(goal)
      (@game_plays_count ||= {})[goal.id] ||= begin
        book_ids = goal.books.map(&:id)
        start_d = [ @mission.start_date, assigned_on ].compact.max
        end_d   = [ @mission.end_date, unassigned_on ].compact.min
        if start_d.nil? || end_d.nil? || end_d < start_d
          0
        else
          scope = @user.game_plays.where(played_on: start_d..end_d)
          scope = scope.where(book_id: book_ids) if book_ids.any?
          scope.count
        end
      end
    end

    def assigned_on
      @participation&.assigned_at&.in_time_zone(ZONE)&.to_date
    end

    def unassigned_on
      @participation&.unassigned_at&.in_time_zone(ZONE)&.to_date
    end
  end
end
