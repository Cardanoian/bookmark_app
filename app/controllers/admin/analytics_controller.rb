# 전교 통합 통계(P7.5). 총괄 = 전역: 전 학교 참여율·5축 평균·전국 랭킹 원자료 집계 +
# 전교 원자료 CSV 내보내기(gem 없이 RFC 4180 직접 인코딩).
class Admin::AnalyticsController < Admin::BaseController
  # Excel 한글 깨짐 방지용 UTF-8 BOM.
  BOM = "﻿"

  def show
    load_global_stats
  end

  def export
    load_global_stats
    csv = build_csv
    audit!(
      "admin.analytics_csv_download",
      metadata: { school_count: @school_stats.size, student_count: @total_students, report_count: @total_reports }
    )
    send_data csv,
              type: "text/csv; charset=utf-8",
              filename: "national_reading_stats_#{Date.current}.csv",
              disposition: "attachment"
  end

  private

  def load_global_stats
    @schools = School.order(:name).to_a
    classrooms_by_school = Classroom.all.to_a.group_by(&:school_id)
    students = User.where(role: :student).to_a
    students_by_school = students.group_by(&:school_id)
    reports = Report.all.to_a
    reports_by_classroom = reports.group_by(&:classroom_id)

    @school_stats = @schools.map do |school|
      class_ids = (classrooms_by_school[school.id] || []).map(&:id)
      school_reports = class_ids.flat_map { |cid| reports_by_classroom[cid] || [] }
      school_students = students_by_school[school.id] || []
      student_ids = school_students.map(&:id)
      writers = school_reports.map(&:user_id).uniq & student_ids
      {
        school: school,
        student_count: school_students.size,
        report_count: school_reports.size,
        participation: participation_ratio(writers.size, school_students.size),
        axis_averages: axis_averages(school_reports)
      }
    end

    @total_students = students.size
    @total_reports = reports.size
    @approved_count = reports.count(&:reviewed?)
    @national_axis = axis_averages(reports)
    @ranking = students.select { |user| user.points.to_i.positive? }
                       .sort_by { |user| -user.points.to_i }
                       .first(20)
  end

  def participation_ratio(writers, total)
    return 0 if total.zero?

    (writers * 100.0 / total).round
  end

  # 5축 평균(rubric 있는 리포트만 집계, 누락축 → 0). { axis => Float }.
  def axis_averages(reports)
    scored = reports.select { |report| report.rubric.present? }
    ReadingDomain::RUBRIC_AXES.index_with do |axis|
      next 0.0 if scored.empty?

      (scored.sum { |report| report.rubric_scores[axis].to_i }.to_f / scored.size).round(2)
    end
  end

  # 전교 원자료 CSV: 학교별 (학교, 학생수, 독후감수, 참여율, 5축 평균).
  def build_csv
    rows = [ csv_header ]
    @school_stats.each { |stat| rows << csv_data_row(stat) }
    BOM + rows.map { |row| encode_row(row) }.join("\r\n") + "\r\n"
  end

  def csv_header
    [
      "학교", "학생수", "독후감수", "참여율(%)",
      *ReadingDomain::RUBRIC_AXES.map { |axis| ReadingDomain::AXIS_LABELS[axis] }
    ]
  end

  def csv_data_row(stat)
    [
      stat[:school].name,
      stat[:student_count],
      stat[:report_count],
      stat[:participation],
      *ReadingDomain::RUBRIC_AXES.map { |axis| stat[:axis_averages][axis] }
    ]
  end

  # RFC 4180: 콤마·따옴표·개행이 포함된 필드는 따옴표로 감싸고 내부 따옴표는 이중화.
  def encode_row(fields)
    fields.map { |field| encode_field(field) }.join(",")
  end

  def encode_field(field)
    value = field.to_s
    return value unless value.match?(/[",\r\n]/)

    %("#{value.gsub('"', '""')}")
  end
end
