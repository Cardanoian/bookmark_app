# 교사 학생별 통계(student-stats). 담임이 "학생 한 명 한 명이 얼마나 읽고·쓰고·참여했는지"를
# 보는 화면. `index` = 선택 학급 학생 전원의 지표 표(정렬 가능), `show` = 학생 1명 상세.
#
# 대시보드(학급 총계)·검토 큐(글 단위)와 달리 **축이 학생**이다. 집계는 전부
# `Teacher::StudentStatsQuery`(GROUP BY 상수 쿼리)에 위임하고 컨트롤러는 스코프·정렬·경계만 맡는다.
# 학급 경계는 `owned_classroom!`/`owned_student!`(Teacher::BaseController)로 강제한다.
class Teacher::StudentStatsController < Teacher::BaseController
  # 표 헤더 정렬 화이트리스트. 위조·미지정 값은 이름순 폴백(교사가 학급 명렬표처럼 읽는 기본).
  SORTS = %w[name reports approved avg games missions challenges points recent].freeze
  # 정렬 방향 화이트리스트. 위조·미지정은 축별 기본값으로 폴백한다.
  DIRECTIONS = %w[asc desc].freeze
  # 축별 기본 방향 — 이름은 명렬표처럼 가나다순, 지표·최근활동은 "많이 한/최근" 먼저(기존 동작 보존).
  DEFAULT_DIRECTIONS = { "name" => "asc" }.freeze
  # 상세 화면의 목록 상한(최근 항목만 — 화면이 길어지는 것과 계산량을 함께 막는다).
  RECENT_REPORTS = 10
  RECENT_ITEMS = 8

  def index
    @classrooms = teacher_classrooms.order(:academic_year, :grade, :class_no).to_a
    @classroom = selected_classroom
    @query = params[:q].to_s.squish
    @students = classroom_students(@classroom)
    @sort = SORTS.include?(params[:sort]) ? params[:sort] : "name"
    @dir = DIRECTIONS.include?(params[:dir]) ? params[:dir] : DEFAULT_DIRECTIONS.fetch(@sort, "desc")
    @rows = sort_rows(Teacher::StudentStatsQuery.new(@students).rows)
    @summary = summarize(@rows)
  end

  def show
    @student = owned_student!(User.find(params[:id]))
    @row = Teacher::StudentStatsQuery.new([ @student ]).rows.first
    @stats = ReadingStats.new(@student)
    @axis_labels = ReadingDomain::RUBRIC_AXES.map { |axis| ReadingDomain::AXIS_LABELS[axis] }
    @weakness = weakness_insight(@row.axis_averages, ReadingDomain.band_for(@student.classroom&.grade))
    @recent_reports = @student.reports.includes(:book).order(created_at: :desc).limit(RECENT_REPORTS).to_a
    @missions = mission_progress
    @challenges = challenge_progress
  end

  private

  # 표는 항상 한 학급만 다룬다(총괄=전 학급이라 전량 집계를 피하고, 교사도 학급별로 읽는 게 자연스럽다).
  # 위조 classroom_id 는 owned_classroom! 이 403 으로 막고, 미지정이면 첫 학급.
  def selected_classroom
    requested = Classroom.find_by(id: params[:classroom_id])
    return owned_classroom!(requested) if requested

    @classrooms.first
  end

  # 이름 검색은 **학급 경계 스코프 위에만** 얹는다(reports#index 필터 관례). 학급은 이미
  # `selected_classroom` 의 `owned_classroom!` 이 403 으로 막으므로 여기서 경계가 넓어지지 않는다.
  # LIKE 특수문자(% _)는 이스케이프해 "%" 한 글자로 전원이 매칭되는 일이 없게 한다.
  def classroom_students(classroom)
    return [] if classroom.nil?

    scope = User.where(classroom_id: classroom.id, role: :student)
    scope = scope.where("name LIKE ? ESCAPE '\\'", "%#{sanitize_like(@query)}%") if @query.present?
    scope.order(:name).to_a
  end

  def sanitize_like(value)
    value.gsub(/[\\%_]/) { |char| "\\#{char}" }
  end

  # 정렬 = 축(@sort) × 방향(@dir). 동점은 **항상 이름 오름차순**으로 묶는다(교사가 명렬표처럼 읽는다).
  #
  # 방향을 부호 반전(`-값.to_f`)으로 표현하지 않는다 — 그 방식은 숫자에만 통해서 `recent` 축의
  # `Date` 를 만나면 `NoMethodError: undefined method 'to_f' for an instance of Date` 로 죽었다
  # (화면 헤더에 링크가 노출돼 있어 담임이 "최근 활동"을 한 번 누르면 500 이었다). 비교 자체를
  # 뒤집으면 Numeric·Date·String 을 같은 코드로 다루고 동점 규칙도 방향에 오염되지 않는다
  # (배열 통째 `reverse` 는 동점 그룹의 이름 순서까지 뒤집으므로 쓰지 않는다).
  def sort_rows(rows)
    direction = @dir == "desc" ? -1 : 1
    rows.sort do |left, right|
      primary = sort_key(left) <=> sort_key(right)
      if primary.nil? || primary.zero?
        left.student.name.to_s <=> right.student.name.to_s
      else
        primary * direction
      end
    end
  end

  # 축별 정렬 키. 축 안에서는 타입이 일정해야 `<=>` 가 성립한다(숫자 축은 숫자, recent 는 Date).
  def sort_key(row)
    case @sort
    when "reports"    then row.reports.to_i
    when "approved"   then row.approved.to_i
    when "avg"        then row.avg_score.to_f
    when "games"      then row.game_plays.to_i
    when "missions"   then row.missions_completed.to_i
    when "challenges" then row.challenges_completed.to_i
    when "points"     then row.student.points.to_i
    when "recent"     then row.last_activity_on || Date.new(0)
    else row.student.name.to_s
    end
  end

  # 학급 요약(표 위 stat-card). 참여율 = 독후감·게임 중 하나라도 한 학생 비율.
  def summarize(rows)
    count = rows.size
    return { students: 0, participation: 0, avg_reports: 0.0, avg_games: 0.0, unstarted: [] } if count.zero?

    {
      students: count,
      participation: (rows.count(&:active?) * 100.0 / count).round,
      avg_reports: (rows.sum(&:approved).to_f / count).round(1),
      avg_games: (rows.sum(&:game_plays).to_f / count).round(1),
      unstarted: rows.reject(&:active?).map { |row| row.student }
    }
  end

  # 가장 낮은 5축 → 그 학생 학년군의 성취기준·추천활동(대시보드 weakness_insight 의 학생 단위 판).
  def weakness_insight(averages, band)
    return nil if averages.values.all?(&:zero?)

    axis, score = averages.min_by { |_, value| value }
    {
      axis: axis,
      label: ReadingDomain::AXIS_LABELS[axis],
      score: score,
      standard: ReadingDomain.achievement_standards(band)[axis],
      activity: ReadingDomain.recommended_activities(band)[axis]
    }
  end

  def mission_progress
    MissionParticipation.where(user_id: @student.id)
                        .includes(mission: { mission_goals: :books })
                        .order(created_at: :desc).limit(RECENT_ITEMS).map do |participation|
      mission = participation.mission
      {
        participation: participation,
        mission: mission,
        progress: Missions::ProgressCalculator.new(mission, @student, participation: participation).call
      }
    end
  end

  def challenge_progress
    ChallengeParticipation.where(user_id: @student.id)
                          .includes(challenge: { challenge_goals: :books })
                          .order(joined_at: :desc).limit(RECENT_ITEMS).map do |participation|
      challenge = participation.challenge
      progress = if challenge.has_goals?
        Challenges::ProgressCalculator.new(challenge, @student, participation: participation).call
      end
      { participation: participation, challenge: challenge, progress: progress }
    end
  end
end
