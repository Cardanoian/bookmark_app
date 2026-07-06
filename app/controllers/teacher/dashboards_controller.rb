# 교사 대시보드(P6.1). 담임 학급의 독후감 통계·5축 평균·약점 인사이트·검토 큐 요약.
class Teacher::DashboardsController < Teacher::BaseController
  def show
    @classrooms = teacher_classrooms.order(:grade, :class_no).to_a
    classroom_ids = @classrooms.map(&:id)
    @reports = Report.where(classroom_id: classroom_ids).includes(:user, :book).to_a
    @students = User.where(classroom_id: classroom_ids, role: :student)

    @total_reports = @reports.size
    @pending_count = @reports.count { |report| !report.reviewed? }
    @a_ratio = a_ratio(@reports)
    @avg_points = @students.average(:points).to_f.round(1)

    @axis_averages = axis_averages(@reports)
    @axis_labels = ReadingDomain::RUBRIC_AXES.map { |axis| ReadingDomain::AXIS_LABELS[axis] }
    @weakness = weakness_insight(@axis_averages)
    @improvement_avg = improvement_summary(@reports)
    @review_queue = @reports.select { |report| !report.reviewed? && report.rubric.present? }
                            .sort_by(&:created_at).first(5)
  end

  private

  # A등급 비율(%). 채점된(level 있는) 독후감 기준.
  def a_ratio(reports)
    scored = reports.select { |report| report.level.present? }
    return 0 if scored.empty?

    (scored.count { |report| report.level == "A" } * 100.0 / scored.size).round
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

  # 고쳐쓰기 향상도 평균(improvement 기록된 것만).
  def improvement_summary(reports)
    improved = reports.select { |report| report.improvement.present? }
    return nil if improved.empty?

    (improved.sum(&:improvement) / improved.size).round(2)
  end
end
