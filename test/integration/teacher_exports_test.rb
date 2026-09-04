require "test_helper"

# P6.3 엑셀 내보내기(대회요건 연구06): 사전·사후 5축 비교 원자료.
# CSV 였다가 XLSX 로 전환했다 — 사유와 이점은 `Exports::XlsxWriter` 주석 참고.
class TeacherExportsTest < ActionDispatch::IntegrationTest
  XLSX_MIME = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet".freeze

  setup do
    @school = School.create!(name: "내보내기학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @teacher = User.create!(school: @school, classroom: @classroom, name: "내보담임", role: :teacher, password: "password")
    @classroom.update!(teacher: @teacher)
    @student = User.create!(school: @school, classroom: @classroom, name: "내보학생", password: "password")

    @original = Report.create!(
      user: @student, classroom: @classroom, book_title: "원본책",
      rubric: { "content" => 3, "emotion" => 3, "life" => 3, "structure" => 3, "spelling" => 3 },
      avg: 3.0, level: "B", ai_status: :done
    )
    @revision = Report.create!(
      user: @student, classroom: @classroom, book_title: "원본책",
      rubric: { "content" => 5, "emotion" => 5, "life" => 5, "structure" => 4, "spelling" => 4 },
      avg: 4.6, level: "A", ai_status: :done,
      revision_of: @original, prev_avg: 3.0, improvement: 1.6
    )
  end

  test "reports_xlsx returns an xlsx workbook with 사전·사후 5축 columns" do
    login_as @teacher
    get teacher_exports_reports_xlsx_path

    assert_response :success
    assert_equal XLSX_MIME, response.media_type
    assert_match(/filename[^;]*\.xlsx/, response.headers["Content-Disposition"])
    assert_equal "PK", response.body.b[0, 2] # ZIP 컨테이너

    header = read_xlsx_sheet(response.body).first
    assert_equal "학생", header.first
    assert_equal "도서", header.second
    ReadingDomain::AXIS_LABELS.each_value do |label|
      assert_includes header, "사전_#{label}"
      assert_includes header, "사후_#{label}"
    end
    assert_equal "향상도", header.last
  end

  test "reports_xlsx includes both the original and the revised 5축 rows" do
    login_as @teacher
    get teacher_exports_reports_xlsx_path

    row = read_xlsx_sheet(response.body).second
    assert_equal @student.name, row.first
    assert_equal "원본책", row.second
    assert_equal "3.0", row[2]  # 사전 평균
    assert_equal "4.6", row[9]  # 사후 평균
    assert_equal "1.6", row.last # 향상도
  end

  # 점수는 문자열이 아니라 숫자 셀이어야 엑셀에서 정렬·평균·차트가 바로 된다.
  test "점수 칸은 숫자 셀이고 이름·제목 칸은 문자열 셀이다" do
    login_as @teacher
    get teacher_exports_reports_xlsx_path

    sheet = Nokogiri::XML(read_xlsx_entry(response.body, "xl/worksheets/sheet1.xml"))
    sheet.remove_namespaces!
    data_row = sheet.css("sheetData > row")[1]

    assert_equal "inlineStr", data_row.css("c").first["t"], "학생 이름은 문자열 셀"
    assert_nil data_row.css("c")[2]["t"], "사전 평균은 숫자 셀(타입 속성 없음)"
    assert_equal "3.0", data_row.css("c")[2].at_css("v").text
  end

  # 책 제목·학생 이름은 학생 자유 입력이다. CSV 시절에는 이런 값이 파일을 여는 순간 수식이 됐다.
  # XLSX 는 문자열 셀에 넣으므로 수식으로 해석될 길이 없다(= 수식 주입 표면 제거).
  test "수식처럼 생긴 책 제목도 문자열 셀로 나간다" do
    formula = %(=HYPERLINK("http://example.com","눌러보세요"))
    Report.create!(user: @student, classroom: @classroom, book_title: formula,
                   rubric: { "content" => 3, "emotion" => 3, "life" => 3, "structure" => 3, "spelling" => 3 },
                   avg: 3.0, level: "B", ai_status: :done)
    login_as @teacher
    get teacher_exports_reports_xlsx_path

    titles = read_xlsx_sheet(response.body).drop(1).map(&:second)
    assert_includes titles, formula

    sheet = Nokogiri::XML(read_xlsx_entry(response.body, "xl/worksheets/sheet1.xml"))
    sheet.remove_namespaces!
    assert_empty sheet.css("f"), "수식 셀(<f>)이 하나도 없어야 한다"
  end

  # CSV 시절의 이스케이프 걱정(쉼표·따옴표)이 XLSX 에서도 값 그대로 보존되는지 고정한다.
  test "쉼표·따옴표가 든 책 제목이 그대로 보존된다" do
    nasty = %(달러구트 꿈 백화점, 두 번째 이야기 "주문하신 꿈은 매진입니다")
    comma_student = User.create!(school: @school, classroom: @classroom, name: "김, 학생", password: "password")
    Report.create!(user: comma_student, classroom: @classroom, book_title: nasty,
                   rubric: { "content" => 3, "emotion" => 3, "life" => 3, "structure" => 3, "spelling" => 3 },
                   avg: 3.0, level: "B", ai_status: :done)
    login_as @teacher
    get teacher_exports_reports_xlsx_path

    rows = read_xlsx_sheet(response.body)
    row = rows.find { |values| values.first == "김, 학생" }
    assert_equal nasty, row.second
  end

  test "a student is forbidden from the xlsx export" do
    login_as @student
    get teacher_exports_reports_xlsx_path
    assert_response :forbidden
  end
end
