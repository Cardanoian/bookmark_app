module Teacher
  # 학생별 활동 통계 배치 집계(교사 학생 통계 화면). 담임이 "누가 얼마나 읽고·쓰고·참여했는지"를
  # 한 화면에서 보도록 독후감·게임·미션·챌린지·커뮤니티 지표를 학생 단위로 모은다.
  #
  # **쿼리 수는 학생 수와 무관하게 상수**다(모두 `GROUP BY user_id` 집계 — 학급 30명이든 1명이든
  # 같은 십수 개 쿼리). 교사 대시보드가 학급 전체를 SQL 로 집계하는 관례(#3, `axis_averages_sql`)를
  # 학생 축으로 확장한 것이며, 행 본문(reports.body)은 한 건도 적재하지 않는다.
  #
  # 5축 평균은 **승인(reviewed) 원본 독후감**만 집계하고 축별로 `teacher_rubric` 이 있으면 그 값을,
  # 없으면 AI `rubric` 값을 쓴다 — `Report#final_rubric_scores`(학생이 '나의 성장'에서 보는 최종
  # 점수)의 SQL 등가물이라 교사 화면과 학생 화면의 점수가 어긋나지 않는다. 미승인 글은 아직 교사
  # 확정 전이라 제외한다(학생에게도 미노출 — `Report#feedback_visible?`).
  #
  # 독후감 편수는 **원본(revision_of_id nil)** 기준이고 고쳐쓰기는 별도 지표(revisions)로 센다.
  # 집계 경계는 학급이 아니라 **학생 본인 활동 전체**다(`ReadingStats` 관례 — 전학 전 기록도 그
  # 학생의 성장 이력이므로 담임 화면에서 감춘다면 오히려 왜곡).
  class StudentStatsQuery
    ZONE = ActiveSupport::TimeZone["Asia/Seoul"]

    Row = Data.define(
      :student, :reports, :revisions, :approved, :pending, :a_grades, :scored,
      :axis_averages, :avg_score, :game_plays, :distinct_games, :game_type_counts,
      :quiz_attempts, :missions_assigned, :missions_completed,
      :challenges_joined, :challenges_completed, :forum_posts, :cheers_received,
      :monsters, :badges, :last_activity_on
    ) do
      # 활동 시작 여부(독후감·게임 어느 쪽이든 1건 이상). 학급 참여율 분모/분자 판정에 쓴다.
      def active?
        reports.positive? || game_plays.positive?
      end
    end

    def initialize(students)
      @students = students.to_a
    end

    def rows
      @rows ||= @students.map { |student| build_row(student) }
    end

    def row_for(student)
      rows.find { |row| row.student.id == student.id }
    end

    private

    def ids
      @ids ||= @students.map(&:id)
    end

    def build_row(student)
      id = student.id
      axes = axis_stats[id] || blank_axis_stats
      total_reports = original_counts[id].to_i
      approved = approved_counts[id].to_i

      Row.new(
        student: student,
        reports: total_reports,
        revisions: revision_counts[id].to_i,
        approved: approved,
        pending: total_reports - approved,
        a_grades: a_grade_counts[id].to_i,
        scored: axes[:scored],
        axis_averages: axes[:averages],
        avg_score: axes[:avg],
        game_plays: game_play_counts[id].to_i,
        distinct_games: distinct_game_counts[id].to_i,
        game_type_counts: game_type_counts[id] || {},
        quiz_attempts: quiz_attempt_counts[id].to_i,
        missions_assigned: mission_counts[id].to_i,
        missions_completed: mission_completed_counts[id].to_i,
        challenges_joined: challenge_counts[id].to_i,
        challenges_completed: challenge_completed_counts[id].to_i,
        forum_posts: forum_post_counts[id].to_i,
        cheers_received: cheer_counts[id].to_i,
        monsters: monster_counts[id].to_i,
        badges: badge_counts[id].to_i,
        last_activity_on: last_activity_on(id)
      )
    end

    # ---- 독후감 -------------------------------------------------------------

    # 제출된 원본 글만. `.submitted` 가 없으면 미제출 초안(사진 판독 직후·고쳐쓰기 미편집)이
    # `pending`(= reports - approved)에 섞여 "검토 대기 1건"이라고 표시되는데, 정작 검토 큐
    # (Teacher::ReviewsController#classroom_scope)에는 아무것도 없어 교사가 찾을 수 없다.
    def original_reports
      Report.submitted.where(user_id: ids, revision_of_id: nil)
    end

    def original_counts
      @original_counts ||= grouped { original_reports.group(:user_id).count }
    end

    def revision_counts
      @revision_counts ||= grouped { Report.where(user_id: ids).where.not(revision_of_id: nil).group(:user_id).count }
    end

    def approved_counts
      @approved_counts ||= grouped { original_reports.where(reviewed: true).group(:user_id).count }
    end

    def a_grade_counts
      @a_grade_counts ||= grouped { original_reports.where(reviewed: true, level: "A").group(:user_id).count }
    end

    # 학생별 5축 평균 1쿼리. 축별 SUM(COALESCE(교사조정, AI, 0)) / 채점편수 —
    # `Report#final_rubric_scores`(축별 교사 조정 우선) 의 SQL 등가물이다.
    def axis_stats
      @axis_stats ||= grouped do
        scored = original_reports.where(reviewed: true).where.not(rubric: nil).where("rubric != '{}'")
        sums = ReadingDomain::RUBRIC_AXES.map { |axis| axis_sum_sql(axis) }

        scored.group(:user_id)
              .pluck(Arel.sql("reports.user_id"), Arel.sql("COUNT(*)"), *sums)
              .to_h { |user_id, count, *totals| [ user_id, axis_row(count, totals) ] }
      end
    end

    # 축 하나의 "교사 조정 우선" 합계 SQL 조각. 축 이름은 `RUBRIC_AXES` 폐집합이지만 SQL 에
    # 문자열 보간으로 끼워 넣지 않고 **바인드로 넘겨 `sanitize_sql_array` 가 인용**하게 한다 —
    # 값이 실제로 안전한 것과 "안전함을 코드에서 읽어낼 수 있는 것"은 다르고, 정적 분석
    # (brakeman SQL Injection)도 보간된 조각은 신뢰할 수 없다고 본다.
    def axis_sum_sql(axis)
      Arel.sql(
        Report.sanitize_sql_array([
          "SUM(COALESCE(json_extract(reports.teacher_rubric, ?), json_extract(reports.rubric, ?), 0))",
          "$.#{axis}", "$.#{axis}"
        ])
      )
    end

    def axis_row(count, totals)
      averages = ReadingDomain::RUBRIC_AXES.each_with_index.to_h do |axis, index|
        [ axis, (totals[index].to_f / count).round(2) ]
      end
      { scored: count, averages: averages, avg: (averages.values.sum / averages.size).round(1) }
    end

    def blank_axis_stats
      { scored: 0, averages: ReadingDomain::RUBRIC_AXES.index_with { 0.0 }, avg: 0.0 }
    end

    # ---- 게임·퀴즈 ----------------------------------------------------------

    def game_plays
      GamePlay.where(user_id: ids)
    end

    def game_play_counts
      @game_play_counts ||= grouped { game_plays.group(:user_id).count }
    end

    def distinct_game_counts
      @distinct_game_counts ||= grouped { game_plays.distinct.group(:user_id).count(:game_type) }
    end

    # { user_id => { "quiz" => 3, "book" => 1, ... } } (상세 화면 종류별 분해용).
    def game_type_counts
      @game_type_counts ||= grouped do
        game_plays.group(:user_id, :game_type).count.each_with_object({}) do |((user_id, type), count), acc|
          (acc[user_id] ||= {})[type] = count
        end
      end
    end

    def quiz_attempt_counts
      @quiz_attempt_counts ||= grouped { QuizAttempt.where(user_id: ids).group(:user_id).count }
    end

    # ---- 미션·챌린지 --------------------------------------------------------

    def mission_counts
      @mission_counts ||= grouped { MissionParticipation.where(user_id: ids).group(:user_id).count }
    end

    def mission_completed_counts
      @mission_completed_counts ||= grouped do
        MissionParticipation.where(user_id: ids).where.not(completed_at: nil).group(:user_id).count
      end
    end

    def challenge_counts
      @challenge_counts ||= grouped { ChallengeParticipation.where(user_id: ids).group(:user_id).count }
    end

    def challenge_completed_counts
      @challenge_completed_counts ||= grouped do
        ChallengeParticipation.where(user_id: ids).where.not(completed_at: nil).group(:user_id).count
      end
    end

    # ---- 커뮤니티·수집 ------------------------------------------------------

    def forum_post_counts
      @forum_post_counts ||= grouped { ForumPost.where(user_id: ids).group(:user_id).count }
    end

    def cheer_counts
      @cheer_counts ||= grouped { Report.where(user_id: ids).group(:user_id).sum(:cheers_count) }
    end

    def monster_counts
      @monster_counts ||= grouped { UserMonster.where(user_id: ids).distinct.group(:user_id).count(:dex_no) }
    end

    def badge_counts
      @badge_counts ||= grouped { UserBadge.where(user_id: ids).group(:user_id).count }
    end

    # ---- 최근 활동 ----------------------------------------------------------

    def last_report_at
      @last_report_at ||= grouped { Report.where(user_id: ids).group(:user_id).maximum(:created_at) }
    end

    def last_played_on
      @last_played_on ||= grouped { game_plays.group(:user_id).maximum(:played_on) }
    end

    # 독후감 제출(datetime → 앱 시간대 날짜)과 게임 완료일(date) 중 늦은 쪽. 둘 다 없으면 nil.
    def last_activity_on(id)
      dates = [ last_report_at[id]&.in_time_zone(ZONE)&.to_date, last_played_on[id] ].compact
      dates.max
    end

    # 학생이 없으면 IN () 쿼리를 아예 보내지 않는다.
    def grouped
      return {} if ids.empty?

      yield
    end
  end
end
