# 교사 학생별 통계(student-stats). 담임이 "학생 한 명 한 명이 얼마나 읽고·쓰고·참여했는지"를
# 보는 화면. `index` = 선택 학급 학생 전원의 지표 표(정렬 가능), `show` = 학생 1명 상세.
#
# 대시보드(학급 총계)·검토 큐(글 단위)와 달리 **축이 학생**이다. 집계는 전부
# `Teacher::StudentStatsQuery`(GROUP BY 상수 쿼리)에 위임하고 컨트롤러는 스코프·정렬·경계만 맡는다.
# 학급 경계는 `owned_classroom!`/`owned_student!`(Teacher::BaseController)로 강제한다.
class Teacher::StudentStatsController < Teacher::BaseController
  # 표 헤더 정렬 화이트리스트. 위조·미지정 값은 이름순 폴백(교사가 학급 명렬표처럼 읽는 기본).
  SORTS = %w[name reports approved avg games missions challenges points recent].freeze
  # 상세 화면의 목록 상한(최근 항목만 — 화면이 길어지는 것과 계산량을 함께 막는다).
  RECENT_REPORTS = 10
  RECENT_ITEMS = 8

  def index
    @classrooms = teacher_classrooms.order(:academic_year, :grade, :class_no).to_a
    @classroom = selected_classroom
    @students = classroom_students(@classroom)
    @sort = SORTS.include?(params[:sort]) ? params[:sort] : "name"
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

  def classroom_students(classroom)
    return [] if classroom.nil?

    User.where(classroom_id: classroom.id, role: :student).order(:name).to_a
  end

  # 지표 내림차순(많이 한 학생 먼저) + 동점은 이름순. 이름·최근활동만 별도 규칙.
  def sort_rows(rows)
    case @sort
    when "reports"    then desc_by(rows) { |row| row.reports }
    when "approved"   then desc_by(rows) { |row| row.approved }
    when "avg"        then desc_by(rows) { |row| row.avg_score }
    when "games"      then desc_by(rows) { |row| row.game_plays }
    when "missions"   then desc_by(rows) { |row| row.missions_completed }
    when "challenges" then desc_by(rows) { |row| row.challenges_completed }
    when "points"     then desc_by(rows) { |row| row.student.points.to_i }
    when "recent"     then desc_by(rows) { |row| row.last_activity_on || Date.new(0) }
    else rows.sort_by { |row| row.student.name.to_s }
    end
  end

  def desc_by(rows)
    rows.sort_by { |row| [ -(yield(row).to_f), row.student.name.to_s ] }
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
