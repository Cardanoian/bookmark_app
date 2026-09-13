require_relative "application_system_test_case"

# 독후감 자동 저장 E2E(2026-09-12 되살림 — docs/improve/베타피드백_통합정리.md §5-1, WR-1).
#
# 베타 검토(09-11)의 재현 절차 그대로 — 쓰고, 저장 버튼을 누르지 않고, 새로고침한다. 그리고
# 자동 저장이 새로 만든 위험 두 가지를 함께 본다.
# · 새 글: 첫 저장이 초안을 만든 뒤 '제출하기'가 create 로 한 편을 더 만들지 않는가.
# · 고쳐쓰기: 저장된 글을 다시 열어도 '수정하기'가 열리고, 누르면 선생님께 다시 가는가.
# headless chrome(chromedriver)이 없으면 건너뛴다(reports_guided_compose_test 와 같은 방어).
class ReportAutosaveSystemTest < ApplicationSystemTestCase
  SAVE_WAIT = 10 # 초. 입력이 멈추고 2초 뒤 저장한다.
  LEAVE_WARNING = "아직 저장하지 못한 내용이 있어요. 이 화면을 나갈까요?" # report_autosave_controller.js 와 같은 문구

  setup do
    @school = School.create!(name: "자동저장시스템학교")
    @classroom = Classroom.create!(school: @school, grade: 3, class_no: 1)
    @teacher = User.create!(school: @school, classroom: @classroom, name: "자동저장시스템담임", role: :teacher, password: "password")
    @classroom.update!(teacher: @teacher)
    @student = User.create!(school: @school, classroom: @classroom, name: "자동저장시스템학생", password: "password",
      nickname: "자동저장닉", ranking_opted_in: true, ai_consent: true, privacy_consent_at: Time.current)
    @book = Book.create!(title: "마틸다", author: "로알드 달", publisher: "시공주니어", category: :recommended)
  end

  test "새 글: 저장 버튼 없이 새로고침해도 글이 남고, 제출하면 한 편만 생긴다" do
    login_via_browser
    visit new_report_path(input_mode: :keyboard, report: { book_id: @book.id, book_title: @book.title })

    text = "마틸다가 책을 좋아하는 모습이 저와 닮았어요."
    find("#report_body_field").fill_in with: text
    assert_selector "[data-report-autosave-target='status']", text: /저장했어요/, wait: SAVE_WAIT

    # 첫 저장이 초안을 만들면 주소가 편집 화면으로 바뀐다 — 새로고침이 빈 새 글이 아니라 이 초안을 연다.
    assert_current_path %r{\A/reports/\d+/edit\z}
    draft = @student.reports.sole
    assert draft.draft?, "자동 저장은 제출이 아니다"
    assert_equal text, draft.body

    page.refresh
    assert_equal text, find("#report_body_field").value

    click_on "제출하기"
    assert_current_path report_path(draft)
    assert_equal 1, @student.reports.count, "첫 저장이 만든 초안을 PATCH 로 내야 한다(create 로 한 편 더 생기면 안 된다)"
    assert draft.reload.submitted?
  rescue Selenium::WebDriver::Error::WebDriverError => e
    skip_without_chrome(e)
  end

  test "고쳐쓰기: 자동 저장된 글을 다시 열어도 '수정하기'로 선생님께 낼 수 있다" do
    original = Report.create!(user: @student, classroom: @classroom, book: @book, book_title: @book.title,
                              body: "마틸다가 좋았어요.", ai_status: :done, input_mode: :keyboard,
                              submitted_at: 2.days.ago, reviewed: true, reviewed_at: 1.day.ago,
                              rubric: { content: 3, emotion: 3, life: 2, structure: 3, spelling: 4 }, avg: 3.0, level: "B")
    login_via_browser
    visit report_path(original)
    click_on "고쳐쓰기"
    assert_current_path %r{\A/reports/\d+/edit\z}

    submit = find("input[type=submit][value='수정하기']")
    assert submit.disabled?, "원본과 같으면 '수정하기'는 잠겨 있다"

    revised = "마틸다가 좋았어요. 허니 선생님이 마틸다를 믿어 준 장면에서 저도 용기가 났어요."
    find("#report_body_field").fill_in with: revised
    assert_selector "[data-report-autosave-target='status']", text: /저장했어요/, wait: SAVE_WAIT

    # 다시 열면 페이지를 연 순간의 본문이 곧 고친 글이다. 기준이 원본이 아니면 여기서 잠긴다.
    page.refresh
    assert_not find("input[type=submit][value='수정하기']").disabled?, "원본에서 고친 글이면 다시 열어도 낼 수 있어야 한다"

    click_on "수정하기"
    assert_current_path %r{\A/reports/\d+\z}
    revision = @student.reports.find_by!(revision_of: original)
    assert revision.submitted?, "고친 글이 선생님께 가야 한다"
    assert_equal revised, revision.body
  rescue Selenium::WebDriver::Error::WebDriverError => e
    skip_without_chrome(e)
  end

  test "질문형 작성: 답을 쓰는 중에도 저장되고, 초안을 만들어 내면 한 편만 생긴다" do
    login_via_browser
    visit new_report_path(input_mode: :keyboard, guided: 1, report: { book_id: @book.id, book_title: @book.title })

    answer = "책 표지의 마틸다가 궁금해서 읽었어요."
    first("textarea[data-report-guide-target='answer']").fill_in with: answer
    # 답을 쓰는 동안은 폼이 숨겨져 있어 질문 영역에 상태를 보여 준다.
    assert_selector "[data-report-guide-target='status']", text: /저장했어요/, wait: SAVE_WAIT

    assert_current_path %r{\A/reports/\d+/edit\z}
    draft = @student.reports.sole
    assert_equal answer, draft.body

    click_on "초안 만들기"
    click_on "제출하기"
    assert_current_path report_path(draft)
    assert_equal 1, @student.reports.count
    assert draft.reload.submitted?
  rescue Selenium::WebDriver::Error::WebDriverError => e
    skip_without_chrome(e)
  end

  # --- 2026-09-13 리뷰 후속: 예전 테스트는 모두 "저장했어요"를 기다린 뒤에 움직여 위험 경로를 못 봤다 ---

  test "질문형 작성: 첫 저장 전에 '질문 없이 바로 쓰기'를 눌러도 쓴 답이 폼에 남고 한 편만 생긴다" do
    login_via_browser
    visit new_report_path(input_mode: :keyboard, guided: 1, report: { book_id: @book.id, book_title: @book.title })

    answer = "마틸다가 도서관에 혼자 가는 장면이 좋았어요."
    first("textarea[data-report-guide-target='answer']").fill_in with: answer
    click_on "질문 없이 바로 쓰기"

    # 새 빈 글로 이동하지 않고 이 자리에서 폼이 열린다 — 쓴 답이 본문에 있다.
    assert_equal answer, find("#report_body_field").value
    assert_no_selector "a[data-report-guide-target='skipLink']"
    assert_selector "[data-report-autosave-target='status']", text: /저장했어요/, wait: SAVE_WAIT
    assert_current_path %r{\A/reports/\d+/edit\z}

    click_on "제출하기"
    draft = @student.reports.sole
    assert_current_path report_path(draft)
    assert draft.reload.submitted?
  rescue Selenium::WebDriver::Error::WebDriverError => e
    skip_without_chrome(e)
  end

  test "새 글: 첫 저장이 날아가는 중에 '제출하기'를 누르면 기다렸다가 그 초안으로 한 편만 낸다" do
    login_via_browser
    visit new_report_path(input_mode: :keyboard, report: { book_id: @book.id, book_title: @book.title })
    delay_autosave_requests(2500)

    find("#report_body_field").fill_in with: "마틸다처럼 저도 책을 좋아해요."
    assert_selector "[data-report-autosave-target='status']", text: "저장 중…", wait: SAVE_WAIT
    click_on "제출하기"

    # 저장이 끝나기 전에는 버튼을 잠그고 기다린다(연타해도 제출이 쌓이지 않는다).
    assert_selector "[data-report-autosave-target='status']", text: "저장하는 중이에요. 끝나면 바로 낼게요."
    assert_selector "input[type=submit][value='제출하기'][disabled]"
    assert_current_path %r{\A/reports/\d+\z}, wait: SAVE_WAIT
    assert_equal 1, @student.reports.count, "첫 저장이 만든 초안을 PATCH 로 내야 한다(create 로 한 편 더 생기면 안 된다)"
    assert @student.reports.sole.submitted?
  rescue Selenium::WebDriver::Error::WebDriverError => e
    skip_without_chrome(e)
  end

  test "오래된 탭: 다른 곳에서 더 고친 초안은 덮지 않고 멈추며, 쓴 글은 저장 안 됨으로 남는다" do
    draft = Report.create!(user: @student, classroom: @classroom, book: @book, book_title: @book.title,
                           body: "학교에서 쓴 글이에요.", input_mode: :keyboard, ai_status: :pending)
    login_via_browser
    visit edit_report_path(draft)

    # 이 화면을 연 뒤에 다른 기기에서 더 썼다.
    draft.update!(body: "학교에서 쓴 글이에요. 집에서 더 쓴 글이에요.")

    find("#report_body_field").send_keys(" 옛 탭")
    assert_selector "[data-report-autosave-target='status']", text: /다른 곳에서 이 글을 더 고쳤어요/, wait: SAVE_WAIT
    assert_equal "학교에서 쓴 글이에요. 집에서 더 쓴 글이에요.", draft.reload.body
    assert autosave_controller_state("dirty"), "저장 못 한 글은 떠날 때 붙잡아야 한다"
  rescue Selenium::WebDriver::Error::WebDriverError => e
    skip_without_chrome(e)
  end

  # 다른 탭에서 로그아웃하거나 다른 계정으로 로그인하면 옛 보안 토큰으로 보낸 저장이 422 를 받는다
  # (test 환경은 CSRF 검사가 꺼져 있어 응답을 흉내 낸다). 예전에는 이 422 를 '저장 끝'으로 처리해
  # "책 제목과 내용을 확인해 주세요"라는 틀린 안내와 함께 떠날 때 경고도 없이 글을 잃었다.
  test "보안 토큰이 바뀐 422 는 저장 끝이 아니다 — 멈추고 새로 고치게 하며 떠날 때 붙잡는다" do
    draft = Report.create!(user: @student, classroom: @classroom, book: @book, book_title: @book.title,
                           body: "쓰다 만 글이에요.", input_mode: :keyboard, ai_status: :pending)
    login_via_browser
    visit edit_report_path(draft)
    answer_autosave_with(status: 422, body: { status: 422, error: "Unprocessable Entity" })

    find("#report_body_field").send_keys(" 더 쓴 글")
    assert_selector "[data-report-autosave-target='status']", text: /화면을 새로 고쳐 주세요/, wait: SAVE_WAIT
    assert_no_selector "[data-report-autosave-target='status']", text: /책 제목과 내용을 확인해/
    assert autosave_controller_state("dirty")
    assert autosave_controller_state("stopped")
  rescue Selenium::WebDriver::Error::WebDriverError => e
    skip_without_chrome(e)
  end

  # 브라우저는 keepalive 요청 본문을 64KiB 까지만 보낸다(넘으면 보내지도 않고 곧바로 실패). 예전에는
  # 아주 긴 글을 쓰고 창을 닫으면 떠나는 순간의 저장이 조용히 실패하고 경고도 없었다(리뷰 #12).
  test "아주 긴 글은 떠날 때 keepalive 없이 보내고 붙잡는다 — 머물면 저장이 끝난다" do
    draft = Report.create!(user: @student, classroom: @classroom, book: @book, book_title: @book.title,
                           body: "쓰다 만 글이에요.", input_mode: :keyboard, ai_status: :pending)
    login_via_browser
    visit edit_report_path(draft)
    record_autosave_requests

    long_text = "마틸다가 책을 읽는다. " * 2_500 # 한글 약 2만 자 — UTF-8 로 64KiB 를 넘는다
    type_into_body(long_text)
    assert dispatch_beforeunload, "keepalive 로 보낼 수 없는 글은 떠날 때 붙잡아야 한다"

    assert_selector "[data-report-autosave-target='status']", text: /저장했어요/, wait: SAVE_WAIT
    assert_equal [ false ], recorded_keepalive_flags, "한도를 넘는 글은 보통 요청으로 보낸다(keepalive 면 곧바로 실패)"
    assert_equal long_text.strip, draft.reload.body.strip
  rescue Selenium::WebDriver::Error::WebDriverError => e
    skip_without_chrome(e)
  end

  test "보통 길이의 글은 떠날 때 keepalive 로 조용히 저장하고 붙잡지 않는다" do
    draft = Report.create!(user: @student, classroom: @classroom, book: @book, book_title: @book.title,
                           body: "쓰다 만 글이에요.", input_mode: :keyboard, ai_status: :pending)
    login_via_browser
    visit edit_report_path(draft)
    record_autosave_requests

    type_into_body("쓰다 만 글이에요. 떠나기 직전에 한 줄 더 썼어요.")
    assert_not dispatch_beforeunload, "잘 돌고 있으면 떠나는 순간 저장만 하고 붙잡지 않는다"

    assert_selector "[data-report-autosave-target='status']", text: /저장했어요/, wait: SAVE_WAIT
    assert_equal [ true ], recorded_keepalive_flags
    assert_equal "쓰다 만 글이에요. 떠나기 직전에 한 줄 더 썼어요.", draft.reload.body
  rescue Selenium::WebDriver::Error::WebDriverError => e
    skip_without_chrome(e)
  end


  # --- 2차 코드 리뷰(e411848) 후속: 브라우저 쪽 계약 ---

  # 새 글 화면 주소를 서버에 알리는 이름·값이 어긋나면 서버 테스트는 통과해도 기능은 죽는다(#6-d).
  test "새 글: 자동 저장 뒤 처음 새 글 주소로 다시 오면 빈 새 글 대신 그 초안이 열린다" do
    login_via_browser
    origin = new_report_path(input_mode: :keyboard, report: { book_id: @book.id, book_title: @book.title })
    visit origin

    text = "앱에서 다른 화면에 다녀와도 이어서 쓸 수 있어요."
    find("#report_body_field").fill_in with: text
    assert_selector "[data-report-autosave-target='status']", text: /저장했어요/, wait: SAVE_WAIT
    draft = @student.reports.sole

    visit origin # 앱은 자동 저장이 바꾼 주소를 모르고 처음 주소로 화면을 다시 연다.
    assert_current_path edit_report_path(draft)
    assert_text "쓰던 글을 이어서 열었어요."
    assert_equal text, find("#report_body_field").value
    assert_equal 1, @student.reports.count
  rescue Selenium::WebDriver::Error::WebDriverError => e
    skip_without_chrome(e)
  end

  # 첫 저장 중에 책 제목을 고치면, 늦게 온 응답이 옛 책 id 를 숨은 칸에 도로 심었다(#6-b).
  test "첫 저장 중에 책 제목을 고치면 늦게 온 응답이 옛 책을 다시 연결하지 않는다" do
    login_via_browser
    visit new_report_path(input_mode: :keyboard, report: { book_id: @book.id, book_title: @book.title })
    delay_autosave_requests(2500)

    find("#report_body_field").fill_in with: "마틸다 다음 권도 읽고 싶어요."
    assert_selector "[data-report-autosave-target='status']", text: "저장 중…", wait: SAVE_WAIT
    find("#report_book_title").send_keys(" 2권")

    assert_selector "[data-report-autosave-target='status']", text: /저장했어요/, wait: SAVE_WAIT
    assert_equal "", find("input[name='report[book_id]']", visible: :all).value, "아이가 바꾼 책을 옛 책으로 되돌리면 안 된다"
  rescue Selenium::WebDriver::Error::WebDriverError => e
    skip_without_chrome(e)
  end

  # 응답 없는 저장 하나가 다음 저장과 제출을 한없이 붙잡지 않게 시간 제한을 둔다(#6-c).
  test "자동 저장 요청에는 시간 제한 신호가 실린다" do
    draft = Report.create!(user: @student, classroom: @classroom, book: @book, book_title: @book.title,
                           body: "쓰다 만 글이에요.", input_mode: :keyboard, ai_status: :pending)
    login_via_browser
    visit edit_report_path(draft)
    execute_script(<<~JS)
      window.__autosaveSignals = []
      const original = window.fetch
      window.fetch = (input, init = {}) => {
        if (isAutosave(init)) window.__autosaveSignals.push(init.signal instanceof AbortSignal)
        return original(input, init)
      }
    JS
    install_autosave_matcher

    find("#report_body_field").send_keys(" 더 쓴 글")
    assert_selector "[data-report-autosave-target='status']", text: /저장했어요/, wait: SAVE_WAIT
    assert_equal [ true ], evaluate_script("window.__autosaveSignals")
  rescue Selenium::WebDriver::Error::WebDriverError => e
    skip_without_chrome(e)
  end

  # 서버는 저장했는데 응답만 끊긴 경우 — 같은 화면의 재시도는 "다른 곳에서 고쳤어요"로 멈추지 않는다(#2).
  test "응답만 잃은 저장의 재시도는 거짓 충돌 없이 저장된다" do
    draft = Report.create!(user: @student, classroom: @classroom, book: @book, book_title: @book.title,
                           body: "쓰다 만 글이에요.", input_mode: :keyboard, ai_status: :pending)
    login_via_browser
    visit edit_report_path(draft)
    lose_first_autosave_response

    find("#report_body_field").send_keys(" 한 줄 더")
    assert_selector "[data-report-autosave-target='status']", text: /잠시 뒤 다시 저장할게요/, wait: SAVE_WAIT
    assert_selector "[data-report-autosave-target='status']", text: /저장했어요/, wait: SAVE_WAIT
    assert_no_text "다른 곳에서 이 글을 더 고쳤어요"
    assert_equal "쓰다 만 글이에요. 한 줄 더", draft.reload.body
  rescue Selenium::WebDriver::Error::WebDriverError => e
    skip_without_chrome(e)
  end

  # 첫 저장(create)의 응답을 잃어도 서버는 이미 초안을 만들었다. 재시도가 초안을 또 만들지 않는다(#4).
  test "새 글: 첫 저장의 응답을 잃어도 재시도가 초안을 한 편 더 만들지 않는다" do
    login_via_browser
    visit new_report_path(input_mode: :keyboard, report: { book_id: @book.id, book_title: @book.title })
    lose_first_autosave_response

    find("#report_body_field").fill_in with: "마틸다가 도서관에 가는 장면이 좋았어요."
    assert_selector "[data-report-autosave-target='status']", text: /잠시 뒤 다시 저장할게요/, wait: SAVE_WAIT
    assert_selector "[data-report-autosave-target='status']", text: /저장했어요/, wait: SAVE_WAIT
    assert_current_path %r{\A/reports/\d+/edit\z}
    assert_equal 1, @student.reports.count
  rescue Selenium::WebDriver::Error::WebDriverError => e
    skip_without_chrome(e)
  end

  # 링크로 떠날 때는 저장이 끝난 것을 확인한 뒤에 간다(5차 리뷰 F2·R2). 날아가던 저장이 끊기면 다시 보내
  # 저장하고 나서 이동한다 — 예전에는 날아가는 저장을 믿고 곧바로 보내 줬다.
  test "저장 중에 링크로 떠나면 저장이 끝난 뒤에 가고, 그 저장이 끊겨도 다시 보내 저장한 뒤 간다" do
    draft = Report.create!(user: @student, classroom: @classroom, book: @book, book_title: @book.title,
                           body: "쓰다 만 글이에요.", input_mode: :keyboard, ai_status: :pending)
    login_via_browser
    visit edit_report_path(draft)
    fail_first_autosave_after(1500)

    find("#report_body_field").send_keys(" 떠나기 직전에 쓴 글")
    assert_selector "[data-report-autosave-target='status']", text: "저장 중…", wait: SAVE_WAIT
    click_on "취소"
    assert_selector "[data-report-autosave-target='status']", text: /끝나면 이동할게요/
    assert_current_path edit_report_path(draft), ignore_query: true

    assert_current_path reports_path, wait: SAVE_WAIT
    assert_equal "쓰다 만 글이에요. 떠나기 직전에 쓴 글", draft.reload.body
    assert_equal [ false, false ], evaluate_script("window.__autosaveKeepalive"), "문서가 남아 있으니 보통 요청으로 다시 보낸다"
  rescue Selenium::WebDriver::Error::WebDriverError => e
    skip_without_chrome(e)
  end

  # '뒤로 가기'(Turbo 복원 방문)는 멈출 수 없다. 저장이 날아가는 중에 떠나고 그 저장이 끊기면, 떠난 뒤 떠나는
  # 순간용 요청(keepalive)으로 딱 한 번 다시 보내 글을 지킨다(2차 리뷰 #5).
  test "저장 중에 뒤로 가기로 떠나고 그 저장이 끊겨도, 떠난 뒤 한 번 더 보내 글을 지킨다" do
    draft = Report.create!(user: @student, classroom: @classroom, book: @book, book_title: @book.title,
                           body: "쓰다 만 글이에요.", input_mode: :keyboard, ai_status: :pending)
    login_via_browser
    visit_via_turbo edit_report_path(draft)
    fail_first_autosave_after(1500)

    find("#report_body_field").send_keys(" 떠나기 직전에 쓴 글")
    assert_selector "[data-report-autosave-target='status']", text: "저장 중…", wait: SAVE_WAIT
    page.go_back
    assert_current_path root_path

    eventually { draft.reload.body == "쓰다 만 글이에요. 떠나기 직전에 쓴 글" }
    # 떠난 뒤에는 타이머로 다시 보내지 않고, 떠나는 순간용 요청(keepalive)으로 딱 한 번 보낸다.
    assert_equal [ false, true ], evaluate_script("window.__autosaveKeepalive")
  rescue Selenium::WebDriver::Error::WebDriverError => e
    skip_without_chrome(e)
  end

  # "다른 곳에서 고쳤어요" 뒤의 '임시 저장'이 다른 기기의 새 글을 덮던 우회로(#3).
  test "다른 곳에서 고쳤다는 안내 뒤 임시 저장을 눌러도 바로 덮지 않고, 쓴 글을 보여 주며 한 번 더 묻는다" do
    draft = Report.create!(user: @student, classroom: @classroom, book: @book, book_title: @book.title,
                           body: "학교에서 쓴 글이에요.", input_mode: :keyboard, ai_status: :pending)
    login_via_browser
    visit edit_report_path(draft)
    draft.update!(body: "학교에서 쓴 글이에요. 집에서 더 쓴 글이에요.")

    find("#report_body_field").send_keys(" 옛 탭")
    assert_selector "[data-report-autosave-target='status']", text: /다른 곳에서 이 글을 더 고쳤어요/, wait: SAVE_WAIT
    click_on "임시 저장"

    assert_text "다른 탭이나 기기에서 이 글을 더 고쳤어요"
    assert_equal "학교에서 쓴 글이에요. 옛 탭", find("#report_body_field").value, "이 화면에서 쓴 글은 그대로 보여 준다"
    assert dispatch_beforeunload, "저장 안 된 글을 보여 주는 화면이라 떠날 때 붙잡는다(3차 리뷰 M3)"
    assert_equal "학교에서 쓴 글이에요. 집에서 더 쓴 글이에요.", draft.reload.body

    click_on "임시 저장" # 한 번 더 누르면 이 화면의 글로 바꾼다.
    assert_text "임시 저장했어요"
    assert_equal "학교에서 쓴 글이에요. 옛 탭", draft.reload.body
  rescue Selenium::WebDriver::Error::WebDriverError => e
    skip_without_chrome(e)
  end


  # --- 3차 코드 리뷰(b67c678) 후속: 되돌려도 통과하던 브라우저 계약 ---

  # 떠난 뒤 실패한 저장은 한 번만 다시 보낸다. 재시도 타이머까지 걸면 떠난 화면의 옛 글을 몇 초 뒤 또 보낸다.
  test "떠난 뒤에는 실패해도 재시도 타이머를 걸지 않는다 — 딱 한 번만 다시 보낸다" do
    draft = Report.create!(user: @student, classroom: @classroom, book: @book, book_title: @book.title,
                           body: "쓰다 만 글이에요.", input_mode: :keyboard, ai_status: :pending)
    login_via_browser
    visit_via_turbo edit_report_path(draft) # 링크 이동은 저장을 기다리므로, 기다릴 수 없는 뒤로 가기로 떠난다
    fail_first_autosave_after(1000, count: 2) # 떠난 뒤의 한 번까지 끊긴다(연결이 아예 없는 상황)

    find("#report_body_field").send_keys(" 떠나기 직전에 쓴 글")
    assert_selector "[data-report-autosave-target='status']", text: "저장 중…", wait: SAVE_WAIT
    # 이제부터 걸리는 긴 타이머(재시도 간격은 5초 이상)를 적는다. 재시도 간격이 실패마다 벌어져(5→15초)
    # 요청 수만 세려면 수십 초를 기다려야 해서, 타이머가 걸리는지를 직접 본다.
    execute_script(<<~JS)
      window.__longTimers = []
      const originalSetTimeout = window.setTimeout
      window.setTimeout = (callback, delay, ...rest) => {
        if (delay >= 5000) window.__longTimers.push(delay)
        return originalSetTimeout(callback, delay, ...rest)
      }
    JS
    page.go_back
    assert_current_path root_path

    eventually { evaluate_script("window.__autosaveKeepalive.length") == 2 } # 떠난 뒤의 한 번까지 끊겼다
    sleep 1.5 # 두 번째 실패가 처리될 시간
    assert_equal [], evaluate_script("window.__longTimers"), "떠난 화면이 재시도 타이머를 걸면 옛 글을 몇 초 뒤 또 보낸다"
    assert_equal 2, evaluate_script("window.__autosaveKeepalive.length")
  rescue Selenium::WebDriver::Error::WebDriverError => e
    skip_without_chrome(e)
  end

  # 실패 뒤에는 입력마다 보내지 않고 벌려 둔 재시도(5초)가 최신 글을 가져간다(2차 리뷰 #9).
  test "저장이 실패한 뒤 더 입력해도 재시도 간격을 지키고, 재시도가 최신 글을 저장한다" do
    draft = Report.create!(user: @student, classroom: @classroom, book: @book, book_title: @book.title,
                           body: "쓰다 만 글이에요.", input_mode: :keyboard, ai_status: :pending)
    login_via_browser
    visit edit_report_path(draft)
    fail_first_autosave_after(0)

    field = find("#report_body_field")
    field.send_keys(" 첫 줄")
    assert_selector "[data-report-autosave-target='status']", text: /잠시 뒤 다시 저장할게요/, wait: SAVE_WAIT
    field.send_keys(" 그리고 둘째 줄")

    sleep 3 # 입력이 멈추고 2초가 지났다 — 예전에는 여기서 곧바로 다시 보냈다.
    assert_equal 1, evaluate_script("window.__autosaveKeepalive.length"), "실패 뒤 입력이 재시도 간격을 건너뛰면 안 된다"

    assert_selector "[data-report-autosave-target='status']", text: /저장했어요/, wait: SAVE_WAIT
    assert_equal "쓰다 만 글이에요. 첫 줄 그리고 둘째 줄", draft.reload.body
  rescue Selenium::WebDriver::Error::WebDriverError => e
    skip_without_chrome(e)
  end

  # 제출이 나가는 중에 쓴 글도 '저장 안 됨'으로 센다 — 제출이 실패하면 저장·경고 대상이어야 한다(2차 리뷰 #8).
  test "제출이 나가는 중에 쓴 글도 저장 안 된 글로 센다" do
    draft = Report.create!(user: @student, classroom: @classroom, book: @book, book_title: @book.title,
                           body: "쓰다 만 글이에요.", input_mode: :keyboard, ai_status: :pending)
    login_via_browser
    visit edit_report_path(draft)

    dirty = evaluate_script(<<~JS)
      (() => {
        const form = document.querySelector("form[data-controller~='report-autosave']")
        const controller = Stimulus.getControllerForElementAndIdentifier(form, "report-autosave")
        controller.submitting = true
        const field = document.querySelector("#report_body_field")
        field.value += " 제출 중에 쓴 글"
        field.dispatchEvent(new Event("input", { bubbles: true }))
        return controller.dirty
      })()
    JS
    assert dirty
  rescue Selenium::WebDriver::Error::WebDriverError => e
    skip_without_chrome(e)
  end


  # --- 4차 코드 리뷰(bce37c8) 후속 ---

  # 브라우저가 요청 순번(입력 횟수)을 싣지 않으면 모든 요청이 0 이 되어, 늦게 도착한 옛 요청을 가르지 못한다(M-A).
  test "자동 저장과 임시 저장은 입력 횟수를 요청 순번으로 싣는다" do
    draft = Report.create!(user: @student, classroom: @classroom, book: @book, book_title: @book.title,
                           body: "쓰다 만 글이에요.", input_mode: :keyboard, ai_status: :pending)
    login_via_browser
    visit edit_report_path(draft)
    install_autosave_matcher
    execute_script(<<~JS)
      window.__autosaveSeqs = []
      const original = window.fetch
      window.fetch = (input, init = {}) => {
        if (isAutosave(init) && init.body instanceof FormData) window.__autosaveSeqs.push(init.body.get("autosave_seq"))
        return original(input, init)
      }
    JS

    field = find("#report_body_field")
    field.send_keys("a")
    eventually { draft.reload.autosave_seq == 1 }
    field.send_keys("bc")
    eventually { draft.reload.autosave_seq == 3 }
    assert_equal %w[1 3], evaluate_script("window.__autosaveSeqs")

    field.send_keys("d")
    click_on "임시 저장" # 자동 저장 전에 누른다 — 제출 직전의 입력 횟수가 실린다.
    assert_text "임시 저장했어요"
    assert_equal 4, draft.reload.autosave_seq
  rescue Selenium::WebDriver::Error::WebDriverError => e
    skip_without_chrome(e)
  end

  # 첫 저장 응답을 잃은 태블릿이 다시 연결되기만 해도 그사이 집에서 쓴 글을 덮었다(H-A). 이제는 멈추고,
  # 새로 고치면 최신 글이 열리도록 주소만 그 초안으로 바꾼다.
  test "첫 저장 응답을 잃은 사이 다른 곳에서 더 쓴 초안은 재시도가 덮지 않고, 주소를 그 초안으로 바꾼다" do
    login_via_browser
    visit new_report_path(input_mode: :keyboard, report: { book_id: @book.id, book_title: @book.title })
    lose_first_autosave_response

    find("#report_body_field").fill_in with: "태블릿에서 쓴 첫 줄"
    assert_selector "[data-report-autosave-target='status']", text: /잠시 뒤 다시 저장할게요/, wait: SAVE_WAIT
    draft = @student.reports.sole # 서버는 이미 만들었다
    draft.update!(body: "집에서 이어 쓴 긴 글", autosave_writer_key: "home-computer-1", autosave_seq: 57)

    assert_selector "[data-report-autosave-target='status']", text: /다른 곳에서 이 글을 더 고쳤어요/, wait: SAVE_WAIT
    assert_current_path edit_report_path(draft)
    assert_equal "집에서 이어 쓴 긴 글", draft.reload.body
    assert_equal 1, @student.reports.count
  rescue Selenium::WebDriver::Error::WebDriverError => e
    skip_without_chrome(e)
  end

  # 입력 오류로 다시 그린 화면도 저장 안 된 글을 보여 준다. 떠나는 순간 조용히 저장하고 보내 주면 같은
  # 이유로 또 거절돼 잃는다 — 붙잡는다(L-B).
  test "입력 오류로 다시 그린 화면은 떠날 때 붙잡는다" do
    draft = Report.create!(user: @student, classroom: @classroom, book: @book, book_title: @book.title,
                           body: "쓰다 만 글이에요.", input_mode: :keyboard, ai_status: :pending)
    login_via_browser
    visit edit_report_path(draft)

    find("#report_book_title").fill_in with: ""
    find("#report_body_field").send_keys(" 제목을 지우고 더 쓴 글")
    click_on "임시 저장"
    assert_selector "[role=alert]", text: /책/
    assert_equal "쓰다 만 글이에요. 제목을 지우고 더 쓴 글", find("#report_body_field").value
    assert dispatch_beforeunload, "저장 안 된 글을 보여 주는 화면이라 떠날 때 붙잡는다"
  rescue Selenium::WebDriver::Error::WebDriverError => e
    skip_without_chrome(e)
  end


  # --- 5차 코드 리뷰(ee11907) 후속 ---

  # '이미 제출했어요' 화면은 버튼이 없어도 text 칸 하나(책 제목)에서 Enter 가 폼을 제출했다 — 승인된 글이 옛 탭의
  # 글로 덮였다(F1). 서버도 거절하지만(통합 테스트) 화면에서 먼저 멈춘다.
  test "'이미 제출했어요' 화면에서 책 제목에 Enter 를 쳐도 폼을 내지 않는다" do
    draft = Report.create!(user: @student, classroom: @classroom, book: @book, book_title: @book.title,
                           body: "학교에서 쓴 글이에요.", input_mode: :keyboard, ai_status: :pending)
    login_via_browser
    visit edit_report_path(draft)
    draft.update!(body: "집에서 다 쓰고 낸 글", submitted_at: Time.current, ai_status: :done, reviewed: true,
                  reviewed_at: Time.current, rubric: { content: 3, emotion: 3, life: 3, structure: 3, spelling: 3 },
                  avg: 3.0, level: "B", teacher_comment: "잘 썼어요")

    find("#report_body_field").send_keys(" 태블릿에서 더 쓴 글")
    click_on "제출하기"
    assert_text "이미 제출했어요"
    record_form_submissions

    find("#report_book_title").send_keys(:enter)
    sleep 1
    assert_equal 0, evaluate_script("window.__formSubmissions"), "이 화면의 글로는 낼 수 없다"
    draft.reload
    assert_equal "집에서 다 쓰고 낸 글", draft.body
    assert draft.reviewed?
  rescue Selenium::WebDriver::Error::WebDriverError => e
    skip_without_chrome(e)
  end

  # 입력 오류로 '저장 안 됨'인 화면에서 저장이 날아가는 중에 링크를 누르면, 예전에는 그 저장을 믿고 확인 없이
  # 떠났다 — 저장이 다시 거절돼 글을 잃었다(F2). 이제 저장 결과를 보고, 거절되면 묻는다.
  test "입력 오류 상태에서 저장이 날아가는 중에 링크를 누르면, 거절된 뒤 묻고 머물 수 있다" do
    draft = Report.create!(user: @student, classroom: @classroom, book: @book, book_title: @book.title,
                           body: "쓰다 만 글이에요.", input_mode: :keyboard, ai_status: :pending)
    login_via_browser
    visit edit_report_path(draft)

    find("#report_book_title").fill_in with: ""
    find("#report_body_field").send_keys(" 제목을 지운 채 쓴 글")
    assert_selector "[data-report-autosave-target='status']", text: /책 제목과 내용을 확인해/, wait: SAVE_WAIT

    delay_autosave_requests(1500)
    count_autosave_requests
    find("#report_body_field").send_keys(" 그리고 더 쓴 글")
    assert_selector "[data-report-autosave-target='status']", text: "저장 중…", wait: SAVE_WAIT
    dismiss_confirm(LEAVE_WARNING, wait: SAVE_WAIT) { click_on "취소" }

    assert_current_path edit_report_path(draft)
    assert_equal "쓰다 만 글이에요. 제목을 지운 채 쓴 글 그리고 더 쓴 글", find("#report_body_field").value
    assert_equal "쓰다 만 글이에요.", draft.reload.body
    # 날아가던 저장과 한 번 더 보낸 저장뿐 — 거절된 뒤에는 다시 보내도 같아 거기서 멈춘다.
    assert_equal 2, evaluate_script("window.__autosaveCount")

    # "나갈래요"를 고르면 한 번만 묻고 떠난다(다시 가는 이동을 또 붙잡지 않는다).
    accept_confirm(LEAVE_WARNING, wait: SAVE_WAIT) { click_on "취소" }
    assert_current_path reports_path, wait: SAVE_WAIT
  rescue Selenium::WebDriver::Error::WebDriverError => e
    skip_without_chrome(e)
  end

  # 입력 오류(422)로 다시 그린 화면도 같다(F2b, 4차 L-B 화면).
  test "입력 오류로 다시 그린 화면에서 저장 중에 링크를 눌러도 묻는다" do
    draft = Report.create!(user: @student, classroom: @classroom, book: @book, book_title: @book.title,
                           body: "쓰다 만 글이에요.", input_mode: :keyboard, ai_status: :pending)
    login_via_browser
    visit edit_report_path(draft)
    find("#report_book_title").fill_in with: ""
    find("#report_body_field").send_keys(" 제목을 지우고 더 쓴 글")
    click_on "임시 저장"
    assert_selector "[role=alert]", text: /책/

    delay_autosave_requests(1500)
    find("#report_body_field").send_keys(" 다시 그린 화면에서 더 쓴 글")
    assert_selector "[data-report-autosave-target='status']", text: "저장 중…", wait: SAVE_WAIT
    dismiss_confirm(LEAVE_WARNING, wait: SAVE_WAIT) { click_on "취소" }

    assert_equal "쓰다 만 글이에요. 제목을 지우고 더 쓴 글 다시 그린 화면에서 더 쓴 글", find("#report_body_field").value
    assert_equal "쓰다 만 글이에요.", draft.reload.body

    # 머물기로 한 뒤에는 떠나는 안내가 남지 않는다 — 다음 저장은 "저장 중…"이다(7차 리뷰 테스트 공백).
    find("#report_book_title").fill_in with: "마틸다"
    assert_selector "[data-report-autosave-target='status']", text: "저장 중…", wait: SAVE_WAIT
    assert_selector "[data-report-autosave-target='status']", text: /저장했어요/, wait: SAVE_WAIT
  rescue Selenium::WebDriver::Error::WebDriverError => e
    skip_without_chrome(e)
  end

  # 다른 기기가 그사이 써서 날아가던 저장이 409 로 거절되는 경우도 같다(R2).
  test "다른 기기의 글 때문에 거절될 저장이 날아가는 중에 링크를 누르면 묻는다" do
    draft = Report.create!(user: @student, classroom: @classroom, book: @book, book_title: @book.title,
                           body: "학교에서 쓴 글이에요.", input_mode: :keyboard, ai_status: :pending)
    login_via_browser
    visit edit_report_path(draft)
    draft.update!(body: "학교에서 쓴 글이에요. 집에서 더 쓴 글.")
    delay_autosave_requests(1500)

    find("#report_body_field").send_keys(" 태블릿에서 더 쓴 문단")
    assert_selector "[data-report-autosave-target='status']", text: "저장 중…", wait: SAVE_WAIT
    dismiss_confirm(LEAVE_WARNING, wait: SAVE_WAIT) { click_on "취소" }

    assert_selector "[data-report-autosave-target='status']", text: /다른 곳에서 이 글을 더 고쳤어요/
    assert_equal "학교에서 쓴 글이에요. 태블릿에서 더 쓴 문단", find("#report_body_field").value
    assert_equal "학교에서 쓴 글이에요. 집에서 더 쓴 글.", draft.reload.body
  rescue Selenium::WebDriver::Error::WebDriverError => e
    skip_without_chrome(e)
  end

  # 로그아웃은 폼 제출이라 이동 전 알림이 서버 응답 뒤에 온다 — 그때는 세션이 지워져 마지막 입력의 저장이
  # 거절됐다(L1). 이제 로그아웃 요청을 멈춰 두고 저장한 뒤 보낸다.
  test "마지막 문장을 쓰고 곧바로 로그아웃해도 그 문장이 저장된다" do
    draft = Report.create!(user: @student, classroom: @classroom, book: @book, book_title: @book.title,
                           body: "쓰다 만 글이에요.", input_mode: :keyboard, ai_status: :pending)
    login_via_browser
    visit edit_report_path(draft)

    find("#report_body_field").send_keys(" 마지막 문장을 쓰고 바로 로그아웃.")
    click_button "로그아웃" # 입력이 멈춘 뒤 2초가 지나기 전
    assert_current_path new_session_path, wait: SAVE_WAIT
    assert_equal "쓰다 만 글이에요. 마지막 문장을 쓰고 바로 로그아웃.", draft.reload.body
  rescue Selenium::WebDriver::Error::WebDriverError => e
    skip_without_chrome(e)
  end

  # 저장이 거절되는 글(입력 오류)이면 로그아웃 전에 묻는다. 머물기를 고르면 로그아웃하지 않고, 나가기를 고르면
  # 한 번만 묻고 로그아웃한다(로그아웃 뒤의 이동을 또 붙잡지 않는다).
  test "저장할 수 없는 글이 있으면 로그아웃 전에 묻고, 머물면 로그아웃하지 않는다" do
    draft = Report.create!(user: @student, classroom: @classroom, book: @book, book_title: @book.title,
                           body: "쓰다 만 글이에요.", input_mode: :keyboard, ai_status: :pending)
    login_via_browser
    visit edit_report_path(draft)
    find("#report_book_title").fill_in with: ""
    find("#report_body_field").send_keys(" 제목을 지운 채 쓴 글")
    assert_selector "[data-report-autosave-target='status']", text: /책 제목과 내용을 확인해/, wait: SAVE_WAIT
    find("#report_body_field").send_keys(" 더")

    dismiss_confirm(LEAVE_WARNING, wait: SAVE_WAIT) { click_button "로그아웃" }
    sleep 1
    assert_current_path edit_report_path(draft)
    # 로그아웃 요청은 나가지 않았다 — 제목을 다시 채우면 그대로 저장된다.
    find("#report_book_title").fill_in with: "마틸다"
    assert_selector "[data-report-autosave-target='status']", text: /저장했어요/, wait: SAVE_WAIT
    assert_equal "쓰다 만 글이에요. 제목을 지운 채 쓴 글 더", draft.reload.body

    find("#report_book_title").fill_in with: ""
    find("#report_body_field").send_keys(" 다시 쓴 글")
    assert_selector "[data-report-autosave-target='status']", text: /책 제목과 내용을 확인해/, wait: SAVE_WAIT
    find("#report_body_field").send_keys(" 더")
    accept_confirm(LEAVE_WARNING, wait: SAVE_WAIT) { click_button "로그아웃" }
    assert_current_path new_session_path, wait: SAVE_WAIT
  rescue Selenium::WebDriver::Error::WebDriverError => e
    skip_without_chrome(e)
  end

  # 자동 저장이 "이미 제출한 글"로 멈추면 새로 고칠 곳을 그 글 화면으로 바꾸고 링크를 준다(LOW-b).
  test "이미 제출한 글로 멈추면 주소를 그 글 화면으로 바꾸고 링크를 준다" do
    draft = Report.create!(user: @student, classroom: @classroom, book: @book, book_title: @book.title,
                           body: "쓰다 만 글이에요.", input_mode: :keyboard, ai_status: :pending)
    login_via_browser
    visit edit_report_path(draft)
    draft.update!(submitted_at: Time.current)

    find("#report_body_field").send_keys(" 뒤늦게 쓴 글")
    assert_selector "[data-report-autosave-target='status']", text: /이미 제출한 글이에요/, wait: SAVE_WAIT
    assert_selector "[data-report-autosave-target='status'] a[href='#{report_path(draft)}']", text: "낸 글 보러 가기"
    assert_current_path report_path(draft)
  rescue Selenium::WebDriver::Error::WebDriverError => e
    skip_without_chrome(e)
  end

  # 떠난 새 글 화면에 늦게 온 첫 저장 응답(201)·충돌 응답(409)이 지금 화면의 주소를 바꾸면, 새로 고칠 때 엉뚱한
  # 화면이 열린다(되돌려도 통과하던 가드 — ADOPTLOC·MUT-G).
  test "뒤로 가기로 떠난 새 글 화면에 늦게 온 응답은 지금 화면의 주소를 바꾸지 않는다" do
    login_via_browser
    visit_via_turbo new_report_path(input_mode: :keyboard, report: { book_id: @book.id, book_title: @book.title })
    delay_autosave_requests(2000)

    find("#report_body_field").fill_in with: "첫 줄"
    assert_selector "[data-report-autosave-target='status']", text: "저장 중…", wait: SAVE_WAIT
    page.go_back
    assert_current_path root_path
    eventually { @student.reports.exists? } # 서버는 초안을 만들었다
    sleep 2.5 # 늦춘 응답이 도착해 처리될 시간
    assert_current_path root_path

    visit_via_turbo new_report_path(input_mode: :keyboard, report: { book_id: @book.id, book_title: "다른 책" })
    answer_autosave_later(1500, status: 409, body: { error: "stale", edit_url: "/reports/424242/edit" })
    find("#report_body_field").fill_in with: "둘째 글"
    assert_selector "[data-report-autosave-target='status']", text: "저장 중…", wait: SAVE_WAIT
    page.go_back
    assert_current_path root_path
    sleep 2
    assert_current_path root_path
  rescue Selenium::WebDriver::Error::WebDriverError => e
    skip_without_chrome(e)
  end

  # 입력 오류로 '저장 안 됨'이 됐다가 고쳐 저장되면 그 표시가 풀려야 한다 — 안 풀리면 떠날 때마다 붙잡고, 떠난 뒤
  # 한 번 더 보내는 저장도 건너뛴다(되돌려도 통과하던 곳 — MUT-AJ).
  test "입력 오류 뒤 고쳐 저장되면 떠날 때 조용히 저장하고 붙잡지 않는다" do
    draft = Report.create!(user: @student, classroom: @classroom, book: @book, book_title: @book.title,
                           body: "쓰다 만 글이에요.", input_mode: :keyboard, ai_status: :pending)
    login_via_browser
    visit edit_report_path(draft)

    find("#report_book_title").fill_in with: ""
    find("#report_body_field").send_keys(" 제목을 지운 채 쓴 글")
    assert_selector "[data-report-autosave-target='status']", text: /책 제목과 내용을 확인해/, wait: SAVE_WAIT
    find("#report_book_title").fill_in with: "마틸다"
    assert_selector "[data-report-autosave-target='status']", text: /저장했어요/, wait: SAVE_WAIT

    type_into_body("쓰다 만 글이에요. 제목을 다시 쓰고 더 쓴 글")
    assert_not dispatch_beforeunload, "고쳐 저장된 뒤에는 떠나는 순간 조용히 저장한다"
    eventually { draft.reload.body == "쓰다 만 글이에요. 제목을 다시 쓰고 더 쓴 글" }
  rescue Selenium::WebDriver::Error::WebDriverError => e
    skip_without_chrome(e)
  end

  # 제출이 연결 문제로 화면을 바꾸지 못하고 끝나면 자동 저장이 다시 돌아야 한다 — 안 그러면 멈춘 채 남아 그 뒤에
  # 쓴 글이 저장되지 않는다(되돌려도 통과하던 곳 — SUBMITEND).
  test "제출이 연결 문제로 실패하면 자동 저장이 다시 돈다" do
    draft = Report.create!(user: @student, classroom: @classroom, book: @book, book_title: @book.title,
                           body: "쓰다 만 글이에요.", input_mode: :keyboard, ai_status: :pending)
    login_via_browser
    visit edit_report_path(draft)
    fail_next_form_submission

    click_on "제출하기"
    eventually { evaluate_script("window.__failedSubmissions") == 1 }
    find("#report_body_field").send_keys(" 실패한 제출 뒤에 쓴 글")

    eventually { draft.reload.body == "쓰다 만 글이에요. 실패한 제출 뒤에 쓴 글" }
    assert draft.draft?
  rescue Selenium::WebDriver::Error::WebDriverError => e
    skip_without_chrome(e)
  end

  # --- 6차 코드 리뷰(6b2f4e6·9b10c5d) 후속: 떠나기 전에 기다리는 행동은 마지막 것 하나만 ---

  # 링크를 누르고 저장을 기다리는 사이 로그아웃을 누르면, 예전에는 먼저 누른 링크가 기다린 뒤 가 버려 로그아웃이
  # 취소됐다 — 공용 태블릿에 로그인이 남았다(F-1).
  test "저장을 기다리는 사이 로그아웃을 누르면 로그아웃이 이긴다" do
    draft = Report.create!(user: @student, classroom: @classroom, book: @book, book_title: @book.title,
                           body: "쓰다 만 글이에요.", input_mode: :keyboard, ai_status: :pending)
    login_via_browser
    visit edit_report_path(draft)
    delay_autosave_requests(2500)

    find("#report_body_field").send_keys(" 떠나기 전에 쓴 글")
    click_on "취소"
    assert_selector "[data-report-autosave-target='status']", text: /끝나면 이동할게요/
    click_button "로그아웃"

    assert_current_path new_session_path, wait: SAVE_WAIT
    assert_equal "쓰다 만 글이에요. 떠나기 전에 쓴 글", draft.reload.body
  rescue Selenium::WebDriver::Error::WebDriverError => e
    skip_without_chrome(e)
  end

  # 같은 사이 '제출하기'를 누르면 제출이 이긴다 — 예전에는 먼저 누른 링크가 저장을 기다린 뒤 가며 제출을 끊었다
  # (F-1). 제출 응답이 저장보다 늦게 오게 해, 기다림이 끝나는 순간 제출이 아직 날아가는 중이게 한다.
  test "저장을 기다리는 사이 제출하기를 누르면 제출이 이긴다" do
    draft = Report.create!(user: @student, classroom: @classroom, book: @book, book_title: @book.title,
                           body: "쓰다 만 글이에요.", input_mode: :keyboard, ai_status: :pending)
    login_via_browser
    visit edit_report_path(draft)
    delay_autosave_requests(1500)
    delay_form_submission_responses(3500)

    find("#report_body_field").send_keys(" 다 쓴 글")
    click_on "취소"
    assert_selector "[data-report-autosave-target='status']", text: /끝나면 이동할게요/
    click_on "제출하기"

    assert_current_path report_path(draft), wait: SAVE_WAIT
    assert_text "독후감을 제출했어요"
    assert draft.reload.submitted?
  rescue Selenium::WebDriver::Error::WebDriverError => e
    skip_without_chrome(e)
  end

  # 첫 저장을 기다리는 제출 중에 링크를 누르고 '나가기'를 고르면, 첫 저장이 끝나도 제출하지 않는다 — 예전에는
  # 기다리던 제출이 그 이동을 취소하고 글을 냈다(6차 리뷰가 범위 밖으로 보고, e411848 부터). 이동이 느리게 끝나게
  # 해 첫 저장이 끝나는 순간 아직 이 화면에 있게 한다.
  test "첫 저장을 기다리는 제출 중에 나가기를 고르면 제출하지 않는다" do
    login_via_browser
    visit new_report_path(input_mode: :keyboard, report: { book_id: @book.id, book_title: @book.title })
    delay_autosave_requests(2000)
    delay_visits_to(reports_path, 4000)

    find("#report_body_field").fill_in with: "마틸다를 읽었어요."
    assert_selector "[data-report-autosave-target='status']", text: "저장 중…", wait: SAVE_WAIT
    click_on "제출하기"
    assert_selector "[data-report-autosave-target='status']", text: "저장하는 중이에요. 끝나면 바로 낼게요."
    accept_confirm(LEAVE_WARNING) { click_on "취소" }

    assert_current_path reports_path, wait: SAVE_WAIT
    draft = @student.reports.sole
    assert draft.draft?, "나가기를 골랐으니 기다리던 제출은 하지 않는다"
  rescue Selenium::WebDriver::Error::WebDriverError => e
    skip_without_chrome(e)
  end

  # 저장이 거절되는 화면에서 로그아웃을 두 번 누르면 확인창이 두 번 떴다(F-2). 마지막 요청만 묻는다.
  test "저장할 수 없는 화면에서 로그아웃을 두 번 눌러도 한 번만 묻는다" do
    draft = Report.create!(user: @student, classroom: @classroom, book: @book, book_title: @book.title,
                           body: "쓰다 만 글이에요.", input_mode: :keyboard, ai_status: :pending)
    login_via_browser
    visit edit_report_path(draft)
    find("#report_book_title").fill_in with: ""
    find("#report_body_field").send_keys(" 제목을 지운 채 쓴 글")
    assert_selector "[data-report-autosave-target='status']", text: /책 제목과 내용을 확인해/, wait: SAVE_WAIT
    delay_autosave_requests(1500)
    find("#report_body_field").send_keys(" 더")

    dismiss_confirm(LEAVE_WARNING, wait: SAVE_WAIT) do
      click_button "로그아웃"
      click_button "로그아웃"
    end
    sleep 2 # 앞 요청의 기다림이 끝날 시간 — 확인창이 또 뜨면 다음 동작이 실패한다
    assert_current_path edit_report_path(draft)
  rescue Selenium::WebDriver::Error::WebDriverError => e
    skip_without_chrome(e)
  end

  # 로그아웃이 연결 문제로 실패해 화면이 남으면, 그 뒤 이 화면이 멈췄을 때 떠나는 경고가 살아 있어야 한다.
  # "나가기로 했다" 표시가 화면 전체에 남던 때는 묻지 않고 떠나 쓴 글을 잃었다(F-3).
  test "로그아웃이 실패해 남은 화면에서도 떠날 때 경고가 살아 있다" do
    draft = Report.create!(user: @student, classroom: @classroom, book: @book, book_title: @book.title,
                           body: "쓰다 만 글이에요.", input_mode: :keyboard, ai_status: :pending)
    login_via_browser
    visit edit_report_path(draft)
    fail_next_form_submission

    find("#report_body_field").send_keys(" 로그아웃 직전에 쓴 글")
    click_button "로그아웃"
    eventually { evaluate_script("window.__failedSubmissions") == 1 }
    assert_current_path edit_report_path(draft)
    assert_equal "쓰다 만 글이에요. 로그아웃 직전에 쓴 글", draft.reload.body

    draft.update!(body: "다른 기기에서 더 쓴 글", autosave_writer_key: "other-device-0001", autosave_seq: 9)
    find("#report_body_field").send_keys(" 태블릿에서 더 쓴 글")
    assert_selector "[data-report-autosave-target='status']", text: /다른 곳에서 이 글을 더 고쳤어요/, wait: SAVE_WAIT
    dismiss_confirm(LEAVE_WARNING, wait: SAVE_WAIT) { click_on "취소" }
    assert_current_path edit_report_path(draft)
  rescue Selenium::WebDriver::Error::WebDriverError => e
    skip_without_chrome(e)
  end

  # 기다리는 동안 더 써도 저장이 잘 되면 묻지 않고 간다 — 예전에는 기다리는 중 입력을 실패로 보고 물었다(F-4).
  test "저장을 기다리는 동안 더 써도 모두 저장하고 묻지 않고 간다" do
    draft = Report.create!(user: @student, classroom: @classroom, book: @book, book_title: @book.title,
                           body: "쓰다 만 글이에요.", input_mode: :keyboard, ai_status: :pending)
    login_via_browser
    visit edit_report_path(draft)
    delay_autosave_requests(1500)

    find("#report_body_field").send_keys(" 첫 줄")
    click_on "취소"
    find("#report_body_field").send_keys(" 기다리며 쓴 글")
    sleep 1.7 # 첫 저장이 끝나고 다음 저장이 날아가는 중
    find("#report_body_field").send_keys(" 그리고 또")

    assert_current_path reports_path, wait: SAVE_WAIT
    assert_equal "쓰다 만 글이에요. 첫 줄 기다리며 쓴 글 그리고 또", draft.reload.body
  rescue Selenium::WebDriver::Error::WebDriverError => e
    skip_without_chrome(e)
  end

  # 저장을 기다리는 사이 뒤로 가기로 떠났으면, 기다림이 끝나도 떠난 화면이 먼저 누른 곳으로 가지 않는다.
  test "저장을 기다리는 사이 뒤로 가기로 떠나면 기다리던 이동을 하지 않는다" do
    draft = Report.create!(user: @student, classroom: @classroom, book: @book, book_title: @book.title,
                           body: "쓰다 만 글이에요.", input_mode: :keyboard, ai_status: :pending)
    login_via_browser
    visit_via_turbo edit_report_path(draft)
    delay_autosave_requests(2000)

    find("#report_body_field").send_keys(" 떠나기 전에 쓴 글")
    click_on "취소"
    assert_selector "[data-report-autosave-target='status']", text: /끝나면 이동할게요/
    page.go_back
    assert_current_path root_path
    sleep 2.5 # 기다림이 끝날 시간
    assert_current_path root_path
  rescue Selenium::WebDriver::Error::WebDriverError => e
    skip_without_chrome(e)
  end

  # 뒤로 가기로 떠난 편집 화면에 늦게 온 "이미 제출" 409 가 지금 화면의 주소를 그 글로 바꾸지 않는다.
  test "뒤로 가기로 떠난 편집 화면에 늦게 온 이미 제출 응답은 지금 화면의 주소를 바꾸지 않는다" do
    draft = Report.create!(user: @student, classroom: @classroom, book: @book, book_title: @book.title,
                           body: "쓰다 만 글이에요.", input_mode: :keyboard, ai_status: :pending)
    login_via_browser
    visit_via_turbo edit_report_path(draft)
    draft.update!(submitted_at: Time.current)
    delay_autosave_requests(1500)

    find("#report_body_field").send_keys(" 뒤늦게 쓴 글")
    assert_selector "[data-report-autosave-target='status']", text: "저장 중…", wait: SAVE_WAIT
    page.go_back
    assert_current_path root_path
    sleep 2
    assert_current_path root_path
  rescue Selenium::WebDriver::Error::WebDriverError => e
    skip_without_chrome(e)
  end

  # --- 7차 코드 리뷰(f874531) 후속 ---

  # '두고 떠나기'를 골라도 그 글의 저장 시도는 끄지 않는다 — 떠나는 순간 한 번 더 보낸다. 두고 떠나기가 "저장됨"으로
  # 세던 때는 그 마지막 저장이 사라졌다(F7-1).
  test "저장이 끊겨 두고 떠나기로 해도 떠나는 순간 한 번 더 보내 글을 지킨다" do
    draft = Report.create!(user: @student, classroom: @classroom, book: @book, book_title: @book.title,
                           body: "쓰다 만 글이에요.", input_mode: :keyboard, ai_status: :pending)
    login_via_browser
    visit edit_report_path(draft)
    fail_first_autosave_after(1000, count: 2)

    find("#report_body_field").send_keys(" 끊긴 채 떠난 글")
    assert_selector "[data-report-autosave-target='status']", text: "저장 중…", wait: SAVE_WAIT
    accept_confirm(LEAVE_WARNING, wait: SAVE_WAIT) { click_on "취소" }

    assert_current_path reports_path, wait: SAVE_WAIT
    eventually { draft.reload.body == "쓰다 만 글이에요. 끊긴 채 떠난 글" }
    assert_equal [ false, false, true ], evaluate_script("window.__autosaveKeepalive"), "두 번 끊긴 뒤 떠나는 순간 keepalive 로 한 번 더"
  rescue Selenium::WebDriver::Error::WebDriverError => e
    skip_without_chrome(e)
  end

  # 기다리던 이동이 다른 행동(제출)에 밀리면 떠나는 안내도 걷는다 — 남으면 그 뒤 모든 저장이 "끝나면 이동할게요"를
  # 띄웠다(F7-2).
  test "밀려난 이동의 안내는 남지 않는다" do
    draft = Report.create!(user: @student, classroom: @classroom, book: @book, book_title: @book.title,
                           body: "쓰다 만 글이에요.", input_mode: :keyboard, ai_status: :pending)
    login_via_browser
    visit edit_report_path(draft)
    delay_autosave_requests(1500)
    fail_next_form_submission

    find("#report_body_field").send_keys(" 첫 줄")
    click_on "취소"
    assert_selector "[data-report-autosave-target='status']", text: /끝나면 이동할게요/
    click_on "제출하기"
    eventually { evaluate_script("window.__failedSubmissions") == 1 }
    sleep 2 # 밀려난 이동의 기다림이 끝날 시간

    find("#report_body_field").send_keys(" 제출이 실패한 뒤 쓴 글")
    assert_selector "[data-report-autosave-target='status']", text: "저장 중…", wait: SAVE_WAIT
    assert_current_path edit_report_path(draft)
  rescue Selenium::WebDriver::Error::WebDriverError => e
    skip_without_chrome(e)
  end

  # 멈춘 화면(다른 기기의 글)에서 로그아웃을 누르고 '나가기'를 고르면 한 번만 묻는다 — 로그아웃 뒤의 이동을 또
  # 붙잡지 않는다(7차 리뷰 테스트 공백).
  test "멈춘 화면에서 로그아웃에 나가기를 고르면 한 번만 묻는다" do
    draft = Report.create!(user: @student, classroom: @classroom, book: @book, book_title: @book.title,
                           body: "학교에서 쓴 글이에요.", input_mode: :keyboard, ai_status: :pending)
    login_via_browser
    visit edit_report_path(draft)
    draft.update!(body: "집에서 더 쓴 글", autosave_writer_key: "home-computer-01", autosave_seq: 7)

    find("#report_body_field").send_keys(" 태블릿 글")
    assert_selector "[data-report-autosave-target='status']", text: /다른 곳에서 이 글을 더 고쳤어요/, wait: SAVE_WAIT
    accept_confirm(LEAVE_WARNING, wait: SAVE_WAIT) { click_button "로그아웃" }
    assert_current_path new_session_path, wait: SAVE_WAIT
  rescue Selenium::WebDriver::Error::WebDriverError => e
    skip_without_chrome(e)
  end

  # 두고 떠나기로 한 글은 다시 붙잡지 않는다 — 로그아웃이 연결 문제로 실패해 화면에 남아도, 창을 닫거나 로그아웃을
  # 다시 누를 때 또 묻지 않는다(그 뒤에 새로 쓴 글이 없으면). 저장할 글(dirty)과 붙잡을 글을 따로 센다(F7-1).
  test "두고 떠나기로 한 글은 로그아웃이 실패해 남아도 다시 붙잡지 않는다" do
    draft = Report.create!(user: @student, classroom: @classroom, book: @book, book_title: @book.title,
                           body: "쓰다 만 글이에요.", input_mode: :keyboard, ai_status: :pending)
    login_via_browser
    visit edit_report_path(draft)
    find("#report_book_title").fill_in with: ""
    find("#report_body_field").send_keys(" 제목을 지운 채 쓴 글")
    assert_selector "[data-report-autosave-target='status']", text: /책 제목과 내용을 확인해/, wait: SAVE_WAIT
    fail_next_form_submission

    accept_confirm(LEAVE_WARNING, wait: SAVE_WAIT) { click_button "로그아웃" }
    eventually { evaluate_script("window.__failedSubmissions") == 1 }
    assert_current_path edit_report_path(draft)
    assert_not dispatch_beforeunload, "두고 떠나기로 한 글은 창을 닫을 때 다시 붙잡지 않는다"

    click_button "로그아웃" # 다시 묻지 않고 로그아웃한다
    assert_current_path new_session_path, wait: SAVE_WAIT
  rescue Selenium::WebDriver::Error::WebDriverError => e
    skip_without_chrome(e)
  end

  # 연결이 끊긴 채 떠나면 한 번 더 보내 보고 곧바로 묻는다 — 실패한 저장 뒤에 거듭 보내지 않는다(7차 리뷰 테스트 공백).
  test "연결이 끊긴 채 떠나면 한 번만 더 보내 보고 묻는다" do
    draft = Report.create!(user: @student, classroom: @classroom, book: @book, book_title: @book.title,
                           body: "쓰다 만 글이에요.", input_mode: :keyboard, ai_status: :pending)
    login_via_browser
    visit edit_report_path(draft)
    fail_first_autosave_after(0, count: 10)

    find("#report_body_field").send_keys(" 끊긴 채 쓴 글")
    assert_selector "[data-report-autosave-target='status']", text: /잠시 뒤 다시 저장할게요/, wait: SAVE_WAIT
    dismiss_confirm(LEAVE_WARNING, wait: SAVE_WAIT) { click_on "취소" }

    assert_equal 2, evaluate_script("window.__autosaveKeepalive.length"), "처음 저장 + 떠나기 전 한 번"
    assert_current_path edit_report_path(draft)
  rescue Selenium::WebDriver::Error::WebDriverError => e
    skip_without_chrome(e)
  end

  private

  # 크롬(chromedriver)을 쓸 수 없을 때만 건너뛴다. 예상 밖의 확인창(UnexpectedAlertOpenError)도 WebDriverError 라,
  # 그대로 건너뛰면 "확인창이 한 번 더 뜬다" 같은 회귀가 실패가 아니라 skip 으로 가려진다(5차 리뷰 후속 변이
  # 실험에서 실제로 세 가지가 이렇게 가려졌다).
  def skip_without_chrome(error)
    raise error if error.is_a?(Selenium::WebDriver::Error::UnexpectedAlertOpenError)

    skip "headless chrome(chromedriver)를 사용할 수 없어 시스템 테스트를 건너뜁니다: #{error.message}"
  end

  # Turbo 로 화면을 연다(링크를 누른 것과 같은 방문). 뒤로 가기가 Turbo 복원 방문이 되게 한다.
  def visit_via_turbo(path)
    execute_script("Turbo.visit(arguments[0])", path)
    assert_current_path path.split("?").first, ignore_query: true
  end

  # 폼 제출(자동 저장이 아닌 POST)의 응답만 ms 늦춘다 — 요청은 곧바로 서버에 닿는다.
  def delay_form_submission_responses(ms)
    install_autosave_matcher
    execute_script(<<~JS, ms)
      const delay = arguments[0]
      const original = window.fetch
      window.fetch = (input, init = {}) => {
        const request = original(input, init)
        const submission = (init.method || "GET").toUpperCase() === "POST" && !isAutosave(init)
        return submission ? request.then((response) => new Promise((resolve) => setTimeout(() => resolve(response), delay))) : request
      }
    JS
  end

  # 그 주소로 가는 Turbo 방문(GET)의 응답만 ms 늦춘다.
  def delay_visits_to(path, ms)
    execute_script(<<~JS, path, ms)
      const [path, delay] = [arguments[0], arguments[1]]
      const original = window.fetch
      window.fetch = (input, init = {}) => {
        const request = original(input, init)
        const url = new URL(typeof input === "string" ? input : input.url, window.location.href)
        const visit = (init.method || "GET").toUpperCase() === "GET" && url.pathname === path
        return visit ? request.then((response) => new Promise((resolve) => setTimeout(() => resolve(response), delay))) : request
      }
    JS
  end

  # 자동 저장 요청 수를 센다(요청은 그대로 보낸다).
  def count_autosave_requests
    install_autosave_matcher
    execute_script(<<~JS)
      window.__autosaveCount = 0
      const original = window.fetch
      window.fetch = (input, init = {}) => {
        if (isAutosave(init)) window.__autosaveCount += 1
        return original(input, init)
      }
    JS
  end

  # Turbo 가 보내는 폼 제출(자동 저장이 아닌 POST)을 센다.
  def record_form_submissions
    install_autosave_matcher
    execute_script(<<~JS)
      window.__formSubmissions = 0
      const original = window.fetch
      window.fetch = (input, init = {}) => {
        if ((init.method || "GET").toUpperCase() === "POST" && !isAutosave(init)) window.__formSubmissions += 1
        return original(input, init)
      }
    JS
  end

  # 다음 폼 제출(자동 저장이 아닌 POST) 하나를 연결 끊김으로 실패시킨다.
  def fail_next_form_submission
    install_autosave_matcher
    execute_script(<<~JS)
      window.__failedSubmissions = 0
      const original = window.fetch
      window.fetch = (input, init = {}) => {
        const submission = (init.method || "GET").toUpperCase() === "POST" && !isAutosave(init)
        if (!submission || window.__failedSubmissions > 0) return original(input, init)
        window.__failedSubmissions += 1
        return Promise.reject(new TypeError("연결이 끊겼다"))
      }
    JS
  end

  # 자동 저장 요청에 서버 대신 정해 둔 응답을 ms 뒤에 돌려준다.
  def answer_autosave_later(ms, status:, body:)
    install_autosave_matcher
    execute_script(<<~JS, ms, status, body.to_json)
      const [delay, status, body] = [arguments[0], arguments[1], arguments[2]]
      const original = window.fetch
      window.fetch = (input, init = {}) => {
        if (!isAutosave(init)) return original(input, init)
        return new Promise((resolve) => setTimeout(() =>
          resolve(new Response(body, { status, headers: { "content-type": "application/json" } })), delay))
      }
    JS
  end

  # 긴 글을 키 입력으로 치면 수십 초가 걸린다. 값을 넣고 입력 이벤트를 흘린다(자동 저장은 input 을 듣는다).
  def type_into_body(text)
    execute_script(<<~JS, text)
      const field = document.querySelector("#report_body_field")
      field.value = arguments[0]
      field.dispatchEvent(new Event("input", { bubbles: true }))
    JS
  end

  # 창을 닫는 순간(beforeunload)을 흉내 낸다. 반환값 = 떠나기 전에 붙잡았는가(preventDefault).
  def dispatch_beforeunload
    evaluate_script(<<~JS)
      (() => {
        const event = new Event("beforeunload", { cancelable: true })
        window.dispatchEvent(event)
        return event.defaultPrevented
      })()
    JS
  end

  # 자동 저장 요청(Accept JSON)마다 keepalive 를 썼는지 기록한다(요청은 그대로 서버로 간다).
  def record_autosave_requests
    install_autosave_matcher
    execute_script(<<~JS)
      window.__autosaveKeepalive = []
      const original = window.fetch
      window.fetch = (input, init = {}) => {
        if (isAutosave(init)) window.__autosaveKeepalive.push(!!init.keepalive)
        return original(input, init)
      }
    JS
  end

  def recorded_keepalive_flags
    evaluate_script("window.__autosaveKeepalive")
  end

  # 페이지에 "자동 저장 요청인가"를 가리는 함수를 심는다(POST + Accept JSON — 책 자동 완성은 GET 이다).
  def install_autosave_matcher
    execute_script(<<~JS)
      window.isAutosave = (init = {}) =>
        (init.method || "GET").toUpperCase() === "POST" && new Headers(init.headers || {}).get("Accept") === "application/json"
    JS
  end

  # 첫 자동 저장은 서버까지 가서 저장되지만 브라우저는 응답을 못 받는다(연결 끊김). 그다음부터는 그대로.
  def lose_first_autosave_response
    install_autosave_matcher
    execute_script(<<~JS)
      let lost = false
      const original = window.fetch
      window.fetch = (input, init = {}) => {
        const request = original(input, init)
        if (!isAutosave(init) || lost) return request
        lost = true
        return request.then(() => { throw new TypeError("응답을 잃었다") })
      }
    JS
  end

  # 앞의 자동 저장 count 개는 서버에 닿지 못하고 ms 뒤 끊긴다. 그다음부터는 그대로.
  # 자동 저장마다 keepalive 를 썼는지 window.__autosaveKeepalive 에 적는다(요청 수도 이걸로 센다).
  def fail_first_autosave_after(ms, count: 1)
    install_autosave_matcher
    execute_script(<<~JS, ms, count)
      const [delay, failures] = [arguments[0], arguments[1]]
      let failed = 0
      window.__autosaveKeepalive = []
      const original = window.fetch
      window.fetch = (input, init = {}) => {
        if (!isAutosave(init)) return original(input, init)
        window.__autosaveKeepalive.push(!!init.keepalive)
        if (failed >= failures) return original(input, init)
        failed += 1
        return new Promise((_, reject) => setTimeout(() => reject(new TypeError("연결이 끊겼다")), delay))
      }
    JS
  end

  def eventually(timeout: SAVE_WAIT)
    deadline = Time.current + timeout
    until yield
      raise Minitest::Assertion, "#{timeout}초 안에 조건을 만족하지 않았습니다" if Time.current > deadline

      sleep 0.2
    end
  end

  # 자동 저장(Accept: application/json)의 **응답만** 늦춘다 — 요청은 곧바로 서버에 닿아 초안이 생기고,
  # 브라우저는 그 사실을 늦게 안다(느린 학교 망). 이 사이에 제출이 기다리지 않으면 create 로 한 편이
  # 더 생긴다. 요청을 늦추면 제출이 먼저 끝나 버려 이 위험을 못 본다. Turbo 의 제출(HTML)은 그대로 둔다.
  def delay_autosave_requests(ms)
    install_autosave_matcher
    execute_script(<<~JS, ms)
      const delay = arguments[0]
      const original = window.fetch
      window.fetch = (input, init = {}) => {
        const json = isAutosave(init)
        const request = original(input, init)
        return json ? request.then((response) => new Promise((resolve) => setTimeout(() => resolve(response), delay))) : request
      }
    JS
  end

  # 자동 저장 요청에 서버 대신 정해 둔 응답을 돌려준다.
  def answer_autosave_with(status:, body:)
    install_autosave_matcher
    execute_script(<<~JS, status, body.to_json)
      const [status, body] = [arguments[0], arguments[1]]
      const original = window.fetch
      window.fetch = (input, init = {}) => {
        const json = isAutosave(init)
        if (!json) return original(input, init)
        return Promise.resolve(new Response(body, { status, headers: { "content-type": "application/json" } }))
      }
    JS
  end

  def autosave_controller_state(name)
    evaluate_script(<<~JS)
      Stimulus.getControllerForElementAndIdentifier(
        document.querySelector("form[data-controller~='report-autosave']"), "report-autosave").#{name}
    JS
  end

  # reports_guided_compose_test 와 같은 브라우저 로그인. 마지막 assert_current_path 는 세션 쿠키가
  # 심길 때까지 기다리는 필수 대기점이다(test/CLAUDE.md "브라우저 로그인 3계약").
  def login_via_browser
    visit student_login_path
    fill_in "학교 이름으로 찾기", with: @school.name
    find("li button", text: @school.name).click
    assert_selector "#classroom_id option", text: @classroom.label
    select @classroom.label, from: "classroom_id"
    fill_in "이름", with: @student.name
    fill_in "비밀번호", with: "password"
    click_button "로그인"
    assert_current_path root_path
  end
end
