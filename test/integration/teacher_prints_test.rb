require "test_helper"

# P6.3 인쇄 문서: 표창장·가정통신문·포트폴리오·학급 성장 리포트(print 레이아웃).
class TeacherPrintsTest < ActionDispatch::IntegrationTest
  # `core-1.3.1.aar` 실측 문자열 + 앱 prefix(native_photo_zoom_test 와 동일 근거).
  NATIVE_UA = "Chaekgalpi Android/1.0.0; Hotwire Native Android; Turbo Native Android; " \
              "Mozilla/5.0 (Linux; Android 12; SM-P610) AppleWebKit/537.36 (KHTML, like Gecko) " \
              "Version/4.0 Chrome/131.0.0.0 Safari/537.36".freeze

  setup do
    @school = School.create!(name: "인쇄학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @teacher = User.create!(school: @school, classroom: @classroom, name: "인쇄담임", role: :teacher, password: "password")
    @classroom.update!(teacher: @teacher)
    @student = User.create!(school: @school, classroom: @classroom, name: "인쇄학생", password: "password")
    Report.create!(
      user: @student, classroom: @classroom, book_title: "인쇄책",
      rubric: { "content" => 4, "emotion" => 4, "life" => 4, "structure" => 3, "spelling" => 3 },
      avg: 3.7, level: "A", ai_status: :done
    )
  end

  test "award renders 200 with the print layout" do
    login_as @teacher
    get award_teacher_prints_path(student_id: @student.id)
    assert_response :success
    assert_match "표 창 장", response.body
    assert_match "인쇄하기", response.body # print layout toolbar
  end

  test "home_letter renders 200 with the print layout" do
    login_as @teacher
    get home_letter_teacher_prints_path(student_id: @student.id)
    assert_response :success
    assert_match "가정통신문", response.body
    assert_match "인쇄하기", response.body
  end

  test "portfolio renders 200 with a radar svg" do
    login_as @teacher
    get portfolio_teacher_prints_path(student_id: @student.id)
    assert_response :success
    assert_match "<svg", response.body
    assert_match "<polygon", response.body
    assert_match "인쇄하기", response.body
  end

  test "class_report renders 200 with the print layout" do
    login_as @teacher
    get class_report_teacher_prints_path(classroom_id: @classroom.id)
    assert_response :success
    assert_match "경험치", response.body
    assert_match "학급 성장 리포트", response.body
    assert_match "인쇄하기", response.body
  end

  # ── 문서 출력 인덱스(계획 Phase 7 별건) ────────────────────────────────
  # 이 화면이 생기기 전까지 인쇄 문서 4종은 **웹·앱 어디에도 링크가 없었다.** URL 을 직접 치는
  # 사람만 닿을 수 있었고, 화면도 오류도 없어서 "기능이 없는 것"과 구별되지 않았다.
  # 링크가 다시 사라지면 여기서 깨진다.

  test "문서 출력 인덱스가 4종 문서 전부로 가는 링크를 낸다" do
    login_as @teacher
    get teacher_prints_path

    assert_response :success
    assert_select "a[href=?]", class_report_teacher_prints_path(classroom_id: @classroom.id), 1
    assert_select "a[href=?]", award_teacher_prints_path(classroom_id: @classroom.id, student_id: @student.id), 1
    assert_select "a[href=?]", home_letter_teacher_prints_path(classroom_id: @classroom.id, student_id: @student.id), 1
    assert_select "a[href=?]", portfolio_teacher_prints_path(classroom_id: @classroom.id, student_id: @student.id), 1
  end

  test "교사 네비가 문서 출력 인덱스로 가는 진입점을 낸다" do
    # 인덱스를 만들어도 네비에 없으면 여전히 아무도 못 찾는다. 진입 동선 자체를 고정한다.
    login_as @teacher
    get teacher_dashboard_path

    assert_response :success
    assert_select "a[href=?]", teacher_prints_path
    assert_match "문서 출력", response.body
  end

  test "문서 출력 인덱스는 인쇄 레이아웃이 아니라 교사 콘솔 레이아웃으로 열린다" do
    login_as @teacher
    get teacher_prints_path

    assert_response :success
    assert_select ".print-toolbar", 0, "print 툴바는 문서 4종에만 있다"
    assert_select "button[onclick='window.print()']", 0
    assert_select "h1", "문서 출력"
    assert_select "a[href=?]", teacher_dashboard_path # 교사 네비가 함께 렌더된다
  end

  test "담당 학급이 없는 교사에게도 403 이 아니라 빈 상태를 보여 준다" do
    # 네비에 상시 노출되는 화면이라, 학급 배정 전 교사가 눌렀다고 권한 오류를 띄우면 안 된다.
    lone_teacher = User.create!(school: @school, name: "무학급담임", role: :teacher,
                                email: "noclass@example.com", password: "password")
    login_as lone_teacher
    get teacher_prints_path

    assert_response :success
    assert_match "담당 학급이 아직 없어요", response.body
  end

  test "남의 학급 id 로 문서 출력 인덱스를 열 수 없다" do
    other_classroom = Classroom.create!(school: @school, grade: 6, class_no: 3)
    other_teacher = User.create!(school: @school, classroom: other_classroom, name: "인덱스타담임",
                                 role: :teacher, password: "password")
    other_classroom.update!(teacher: other_teacher)

    login_as other_teacher
    get teacher_prints_path(classroom_id: @classroom.id)
    assert_response :forbidden
  end

  test "학생은 문서 출력 인덱스에 접근할 수 없다" do
    login_as @student
    get teacher_prints_path
    assert_response :forbidden
  end

  test "웹은 문서를 새 탭으로 열고 앱은 같은 스택에서 연다" do
    # WebView 는 target=\"_blank\" 를 무시해 링크가 **아무 일도 하지 않는다**(_ocr_photo 선례).
    # 웹의 새 탭 동작은 그대로 두고 앱에서만 target 을 뗀다.
    login_as @teacher

    get teacher_prints_path
    assert_select "a[href=?][target=?]", class_report_teacher_prints_path(classroom_id: @classroom.id), "_blank"

    get teacher_prints_path, headers: { "User-Agent" => NATIVE_UA }
    assert_select "a[href=?]", class_report_teacher_prints_path(classroom_id: @classroom.id), 1
    assert_select "a[href=?][target]", class_report_teacher_prints_path(classroom_id: @classroom.id), 0
  end

  # 원자료 엑셀은 담임 학급 **전체**를 내보내는 학급-무관 산출물이고, 이 화면이 유일한 진입점이라
  # 학급 유무와 무관하게 닿아야 한다. 학급 분기 안쪽에 두면 학급 없는 교사가 경로를 잃는다.
  test "index shows the raw export section with its purpose explained" do
    login_as @teacher
    get teacher_prints_path

    assert_response :success
    assert_select "section#raw-export" do
      assert_select "a[href=?]", teacher_exports_reports_xlsx_path
    end
    assert_match "AI에게", response.body, "원자료 용도(AI 분석) 안내가 있어야 한다"
  end

  # 네비의 "CSV 내보내기"는 목적지가 "문서 출력"과 같은 화면(#raw-export 앵커)이라 메뉴만 둘로
  # 보였다. 항목을 없앤 대신 그 카드가 화면 첫 카드로 남아야 한다(진입 경로가 사라지면 안 된다).
  test "교사 네비에 원자료 내려받기 전용 항목이 따로 있지 않다" do
    login_as @teacher
    get teacher_dashboard_path

    assert_response :success
    assert_select "a[href=?]", teacher_prints_path(anchor: "raw-export"), 0
    assert_no_match "CSV 내보내기", response.body
    assert_no_match "엑셀 내보내기", response.body
    assert_select "a[href=?]", teacher_prints_path # 문서 출력 진입점은 남는다
  end

  test "index still shows the raw export section for a teacher with no classroom" do
    classroomless = User.create!(school: @school, name: "무학급담임", role: :teacher,
                                 email: "noclass@example.com", password: "password")
    login_as classroomless
    get teacher_prints_path

    assert_response :success
    assert_select "section#raw-export a[href=?]", teacher_exports_reports_xlsx_path
  end

  # 앱은 링크 마크업이 아니라 원격 Path Configuration 의 URL 패턴으로 다운로드를 판정한다.
  # Turbo 방문이 제안되어야 그 핸들러가 잡으므로 data-turbo="false" 를 붙이면 안 된다(2026-09-03 실측).
  test "the download link keeps the markup the Android download handler relies on" do
    login_as @teacher
    get teacher_prints_path

    assert_select "section#raw-export a[href=?]", teacher_exports_reports_xlsx_path do |links|
      assert_nil links.first["data-turbo"], "data-turbo 를 끄면 앱의 다운로드 훅이 사라진다"
      assert_nil links.first["target"], "내려받는 파일은 새 탭에서 여는 문서가 아니다"
    end
  end

  # 스프라이트 아이콘은 잉크색(#1F2A44)이 symbol 안에 박혀 있어, 어두운 버튼 위에 그냥 두면
  # 배경에 묻혀 보이지 않는다(외부 <use> 라 바깥 CSS 의 color/stroke 로는 못 바꾼다).
  # icon-inverse 가 흰 실루엣으로 뒤집는다 — 클래스가 빠지면 아이콘이 다시 사라진다.
  test "the download button icon is inverted to white on the dark button" do
    login_as @teacher
    get teacher_prints_path

    assert_select "section#raw-export a[href=?].btn-primary svg.icon-inverse",
                  teacher_exports_reports_xlsx_path, 1
  end

  # 예시 문장은 <details>/<summary> 가 아니라 내려받기 버튼 옆의 배경색 버튼 + 그 아래 전폭 패널이다
  # (summary 를 버튼 행에 두면 열린 내용까지 그 줄로 끌려온다). 여닫이는 disclosure 컨트롤러가 맡고,
  # JS 가 없으면 패널이 펼쳐진 채 남아 예시 문장을 잃지 않는다.
  test "the AI prompt example sits beside the download button as a filled toggle" do
    login_as @teacher
    get teacher_prints_path

    assert_select "section#raw-export[data-controller~=?]", "disclosure"
    assert_select "section#raw-export button.btn.btn-blue[data-action=?][aria-controls=?]",
                  "disclosure#toggle", "ai-prompt-example" do |buttons|
      assert_match "AI에게 물어볼 문장 예시 보기", buttons.first.text
    end
    assert_select "section#raw-export #ai-prompt-example[data-disclosure-target=?]", "panel" do
      assert_select "textarea[data-clipboard-target=?]", "source"
    end
    assert_select "section#raw-export details", 0, "여닫이는 details 가 아니라 버튼이 맡는다"
  end

  test "a student is forbidden from print documents" do
    login_as @student
    get award_teacher_prints_path(student_id: @student.id)
    assert_response :forbidden
  end

  test "a non-담임 teacher cannot print another classroom's student" do
    other_classroom = Classroom.create!(school: @school, grade: 5, class_no: 2)
    other_teacher = User.create!(school: @school, classroom: other_classroom, name: "인쇄타담임", role: :teacher, password: "password")
    other_classroom.update!(teacher: other_teacher)

    login_as other_teacher
    get award_teacher_prints_path(classroom_id: @classroom.id, student_id: @student.id)
    assert_response :forbidden
  end

  private
end
