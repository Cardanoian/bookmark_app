# 교사 대시보드(P6.1). 담임 학급의 독후감 통계·5축 평균·약점 인사이트·검토 큐 요약.
class Teacher::DashboardsController < Teacher::BaseController
  def show
    @classrooms = teacher_classrooms.order(:grade, :class_no).to_a
    classroom_ids = @classrooms.map(&:id)
    # 전체 리포트 본문을 메모리에 적재하지 않는다. 단순 집계는 SQL COUNT/SUM 으로,
    # 5축 평균은 rubric 컬럼만 적재(본문 제외)해 계산한다(§3.4, 성능E).
    reports = Report.where(classroom_id: classroom_ids)
    @students = User.where(classroom_id: classroom_ids, role: :student)

    @total_reports = reports.count
    @pending_count = reports.where(reviewed: false).count
    @a_ratio = a_ratio(reports)
    @avg_points = @students.average(:points).to_f.round(1)

    @axis_averages = axis_averages(reports) # Relation → SQL 집계(본문·행 미적재)
    @axis_labels = ReadingDomain::RUBRIC_AXES.map { |axis| ReadingDomain::AXIS_LABELS[axis] }
    @weakness = weakness_insight(@axis_averages)
    @improvement_avg = improvement_summary(reports)
    @review_queue = reports.where(reviewed: false).where.not(rubric: nil)
                           .includes(:user, :book).order(:created_at).limit(5).to_a
  end

  private

  # A등급 비율(%). 채점된(level 있는) 독후감 기준. 로우 적재 없이 SQL COUNT 로 집계.
  def a_ratio(reports)
    scored = reports.where.not(level: [ nil, "" ]).count
    return 0 if scored.zero?

    (reports.where(level: "A").count * 100.0 / scored).round
  end

  # 가장 낮은 5축 → 추천 활동 + 성취기준 코드.
  def weakness_insight(averages)
    return nil if averages.values.all?(&:zero?)

    axis, score = averages.min_by { |_, value| value }
    {
      axis: axis,
      label: ReadingDomain::AXIS_LABELS[axis],
      score: score,
      standard: ReadingDomain::ACHIEVEMENT_STANDARDS[axis],
      activity: ReadingDomain::RECOMMENDED_ACTIVITIES[axis]
    }
  end

  # 고쳐쓰기 향상도 평균(improvement 기록된 것만). 로우 적재 없이 SQL COUNT/SUM 으로 집계.
  def improvement_summary(reports)
    scoped = reports.where.not(improvement: nil)
    count = scoped.count
    return nil if count.zero?

    (scoped.sum(:improvement) / count).round(2)
  end
end
