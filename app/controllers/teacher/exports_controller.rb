# 교사 문서 출력 — CSV(P6.3). 담임 학급 독후감의 사전·사후 5축 비교 원자료.
# 대회요건(연구06): 원본(사전) 5축 + 고쳐쓰기(사후) 5축 + 향상도를 학생별로 내보낸다.
# 외부 의존(gem) 없이 RFC 4180 규칙으로 직접 인코딩한다.
class Teacher::ExportsController < Teacher::BaseController
  # Excel 한글 깨짐 방지용 UTF-8 BOM.
  BOM = "﻿"

  def reports_csv
    reports = Report.where(classroom_id: teacher_classrooms.select(:id), revision_of_id: nil)
                    .includes(:user, :book, :revisions)
                    .order(:user_id, :created_at)

    send_data build_csv(reports),
              type: "text/csv; charset=utf-8",
              filename: "reports_5axis_#{Date.current}.csv",
              disposition: "attachment"
  end

  private

  def build_csv(reports)
    rows = [ header_row ]
    reports.each { |report| rows << data_row(report, latest_revision(report)) }
    BOM + rows.map { |row| encode_row(row) }.join("\r\n") + "\r\n"
  end

  def header_row
    [
      "학생", "도서",
      "사전_평균", "사전_등급",
      *ReadingDomain::RUBRIC_AXES.map { |axis| "사전_#{ReadingDomain::AXIS_LABELS[axis]}" },
      "사후_평균", "사후_등급",
      *ReadingDomain::RUBRIC_AXES.map { |axis| "사후_#{ReadingDomain::AXIS_LABELS[axis]}" },
      "향상도"
    ]
  end

  def data_row(report, revision)
    pre = report.rubric_scores
    post = revision&.rubric_scores || {}
    [
      report.user.name,
      report.book&.title.presence || report.book_title,
      report.avg, report.level,
      *ReadingDomain::RUBRIC_AXES.map { |axis| pre[axis] },
      revision&.avg, revision&.level,
      *ReadingDomain::RUBRIC_AXES.map { |axis| post[axis] },
      revision&.improvement
    ]
  end

  def latest_revision(report)
    report.revisions.max_by(&:created_at)
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
