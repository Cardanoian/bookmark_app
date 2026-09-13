# 교사 문서 출력 — 엑셀(P6.3). 담임 학급 독후감의 사전·사후 5축 비교 원자료.
# 대회요건(연구06): 원본(사전) 5축 + 고쳐쓰기(사후) 5축 + 향상도를 학생별로 내보낸다.
# 학생 직접 식별정보는 내보내지 않고, 서버 비밀키로 만든 안정적인 가명 ID만 넣는다(ST-1).
#
# 예전에는 같은 표를 CSV 로 손수 인코딩해 내보냈다(RFC 4180 직접 구현 + 엑셀 한글 깨짐 방지 BOM).
# 쉼표·따옴표가 든 책 제목은 그 인코더가 정확히 처리했지만, **책 제목이 학생 자유 입력**이라
# `=HYPERLINK("http://…","눌러보세요")` 같은 값이 CSV 를 여는 순간 엑셀 수식이 되는 표면이
# 남아 있었다. XLSX 는 셀 타입이 분리돼 있어 문자열 셀이 수식으로 해석되지 않으므로 그 표면이
# 구조적으로 사라진다(부수 효과로 BOM 꼼수와 인코딩 협상도 없어지고, 점수가 숫자로 들어간다).
class Teacher::ExportsController < Teacher::BaseController
  SHEET_NAME = "5축 사전사후".freeze
  FILENAME_PREFIX = "reports_5axis".freeze
  EXPORT_SCHEMA_VERSION = 2
  PSEUDONYM_PURPOSE = "teacher-reports-xlsx-v1".freeze
  PSEUDONYM_HEX_LENGTH = 12

  def reports_xlsx
    reports = Report.where(classroom_id: teacher_classrooms.select(:id), revision_of_id: nil)
                    .includes(:user, :book, :revisions)
                    .order(:user_id, :created_at)
                    .to_a
    pseudonyms = reports.map(&:user_id).uniq.index_with { |user_id| pseudonym_for(user_id) }
    workbook = Exports::XlsxWriter.build(
      headers: header_row,
      rows: reports.map { |report| data_row(report, latest_revision(report), pseudonyms.fetch(report.user_id)) },
      sheet_name: SHEET_NAME
    )
    audit!(
      "teacher.reports_xlsx_download",
      school_id: Current.user.school_id,
      metadata: {
        report_count: reports.size,
        student_count: pseudonyms.size,
        classroom_ids: teacher_classrooms.pluck(:id),
        export_schema_version: EXPORT_SCHEMA_VERSION,
        direct_identifiers_removed: true
      }
    )

    send_data workbook,
              type: Exports::XlsxWriter::CONTENT_TYPE,
              filename: "#{FILENAME_PREFIX}_#{Date.current}.xlsx",
              disposition: "attachment"
  end

  private

  def header_row
    [
      "학생 가명 ID", "도서",
      "사전_평균", "사전_등급",
      *ReadingDomain::RUBRIC_AXES.map { |axis| "사전_#{ReadingDomain::AXIS_LABELS[axis]}" },
      "사후_평균", "사후_등급",
      *ReadingDomain::RUBRIC_AXES.map { |axis| "사후_#{ReadingDomain::AXIS_LABELS[axis]}" },
      "향상도"
    ]
  end

  def data_row(report, revision, student_pseudonym)
    pre = report.rubric_scores
    post = revision&.rubric_scores || {}
    [
      student_pseudonym,
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

  # 같은 학생은 여러 행·여러 다운로드에서 같은 가명 ID를 쓰되, DB id 자체나 대응표는 파일에 넣지
  # 않는다. 학교와 사용자를 키가 있는 HMAC 입력으로 묶어 단순한 id 대입으로 역산할 수 없게 한다.
  # PSEUDONYM_PURPOSE를 바꾸지 않는 한 안정적이고, 형식 변경 시에는 EXPORT_SCHEMA_VERSION도 올린다.
  def pseudonym_for(user_id)
    digest = OpenSSL::HMAC.hexdigest(
      "SHA256",
      pseudonym_key,
      "school:#{Current.user.school_id}:user:#{user_id}"
    )
    "학생-#{digest.first(PSEUDONYM_HEX_LENGTH).upcase}"
  end

  def pseudonym_key
    @pseudonym_key ||= Rails.application.key_generator.generate_key(PSEUDONYM_PURPOSE, 32)
  end
end
