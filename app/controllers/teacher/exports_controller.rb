# 교사 문서 출력 — 엑셀(P6.3). 담임 학급 독후감의 사전·사후 5축 비교 원자료.
# 대회요건(연구06): 원본(사전) 5축 + 고쳐쓰기(사후) 5축 + 향상도를 학생별로 내보낸다.
#
# 예전에는 같은 표를 CSV 로 손수 인코딩해 내보냈다(RFC 4180 직접 구현 + 엑셀 한글 깨짐 방지 BOM).
# 쉼표·따옴표가 든 책 제목은 그 인코더가 정확히 처리했지만, **책 제목·학생 이름이 학생 자유 입력**
# 이라 `=HYPERLINK("http://…","눌러보세요")` 같은 값이 CSV 를 여는 순간 엑셀 수식이 되는 표면이
# 남아 있었다. XLSX 는 셀 타입이 분리돼 있어 문자열 셀이 수식으로 해석되지 않으므로 그 표면이
# 구조적으로 사라진다(부수 효과로 BOM 꼼수와 인코딩 협상도 없어지고, 점수가 숫자로 들어간다).
class Teacher::ExportsController < Teacher::BaseController
  SHEET_NAME = "5축 사전사후".freeze
  FILENAME_PREFIX = "reports_5axis".freeze

  def reports_xlsx
    reports = Report.where(classroom_id: teacher_classrooms.select(:id), revision_of_id: nil)
                    .includes(:user, :book, :revisions)
                    .order(:user_id, :created_at)
    workbook = Exports::XlsxWriter.build(
      headers: header_row,
      rows: reports.map { |report| data_row(report, latest_revision(report)) },
      sheet_name: SHEET_NAME
    )
    audit!(
      "teacher.reports_xlsx_download",
      school_id: Current.user.school_id,
      metadata: { report_count: reports.size, classroom_ids: teacher_classrooms.pluck(:id) }
    )

    send_data workbook,
              type: Exports::XlsxWriter::CONTENT_TYPE,
              filename: "#{FILENAME_PREFIX}_#{Date.current}.xlsx",
              disposition: "attachment"
  end

  private

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
end
