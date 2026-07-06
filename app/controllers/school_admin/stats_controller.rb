# 교무관리자 전교 통계(P6.4). 자기 학교의 참여율·학년/학급별 5축 평균·약점 진단.
# 모든 집계는 current_school 로 스코프 — 타학교 데이터는 노출하지 않는다(경계).
class SchoolAdmin::StatsController < SchoolAdmin::BaseController
  def show
    @school = current_school
    @classrooms = @school ? @school.classrooms.order(:grade, :class_no).to_a : []
    classroom_ids = @classrooms.map(&:id)

    @students = User.where(classroom_id: classroom_ids, role: :student)
    student_ids = @students.pluck(:id)
    @student_count = student_ids.size

    @reports = Report.where(classroom_id: classroom_ids).includes(:user).to_a

    writer_ids = @reports.map(&:user_id).uniq & student_ids
    @participation = participation_ratio(writer_ids.size, @student_count)

    @axis_averages = axis_averages(@reports)
    @axis_labels = ReadingDomain::RUBRIC_AXES.map { |axis| ReadingDomain::AXIS_LABELS[axis] }
    @weakness = weakness_insight(@axis_averages)

    @classroom_stats = classroom_statistics(@classrooms, student_ids)
    @grade_stats = grade_statistics(@classrooms)
  end

  private

  def participation_ratio(writers, total)
    return 0 if total.zero?

    (writers * 100.0 / total).round
  end

  # 학급별 { classroom, report_count, participation, axis_averages }.
  def classroom_statistics(classrooms, student_ids)
    classrooms.map do |classroom|
      reports = @reports.select { |report| report.classroom_id == classroom.id }
      class_students = @students.select { |student| student.classroom_id == classroom.id }
      writers = reports.map(&:user_id).uniq & student_ids
      {
        classroom: classroom,
        report_count: reports.size,
        participation: participation_ratio(writers.size, class_students.size),
        axis_averages: axis_averages(reports)
      }
    end
  end

  # 학년별 { grade, report_count, axis_averages } (오름차순).
  def grade_statistics(classrooms)
    ids_by_grade = classrooms.group_by(&:grade).transform_values { |list| list.map(&:id) }
    ids_by_grade.sort_by { |grade, _| grade.to_i }.map do |grade, class_ids|
      reports = @reports.select { |report| class_ids.include?(report.classroom_id) }
      { grade: grade, report_count: reports.size, axis_averages: axis_averages(reports) }
    end
  end

  # 가장 낮은 5축 → 성취기준 코드 + 추천 활동(약점 진단).
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
end
