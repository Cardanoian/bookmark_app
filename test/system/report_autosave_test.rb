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
    skip "headless chrome(chromedriver)를 사용할 수 없어 시스템 테스트를 건너뜁니다: #{e.message}"
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
    skip "headless chrome(chromedriver)를 사용할 수 없어 시스템 테스트를 건너뜁니다: #{e.message}"
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
    skip "headless chrome(chromedriver)를 사용할 수 없어 시스템 테스트를 건너뜁니다: #{e.message}"
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
    skip "headless chrome(chromedriver)를 사용할 수 없어 시스템 테스트를 건너뜁니다: #{e.message}"
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
    skip "headless chrome(chromedriver)를 사용할 수 없어 시스템 테스트를 건너뜁니다: #{e.message}"
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
    skip "headless chrome(chromedriver)를 사용할 수 없어 시스템 테스트를 건너뜁니다: #{e.message}"
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
    skip "headless chrome(chromedriver)를 사용할 수 없어 시스템 테스트를 건너뜁니다: #{e.message}"
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
    skip "headless chrome(chromedriver)를 사용할 수 없어 시스템 테스트를 건너뜁니다: #{e.message}"
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
    skip "headless chrome(chromedriver)를 사용할 수 없어 시스템 테스트를 건너뜁니다: #{e.message}"
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
    skip "headless chrome(chromedriver)를 사용할 수 없어 시스템 테스트를 건너뜁니다: #{e.message}"
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
    skip "headless chrome(chromedriver)를 사용할 수 없어 시스템 테스트를 건너뜁니다: #{e.message}"
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
    skip "headless chrome(chromedriver)를 사용할 수 없어 시스템 테스트를 건너뜁니다: #{e.message}"
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
    skip "headless chrome(chromedriver)를 사용할 수 없어 시스템 테스트를 건너뜁니다: #{e.message}"
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
    skip "headless chrome(chromedriver)를 사용할 수 없어 시스템 테스트를 건너뜁니다: #{e.message}"
  end

  # 저장이 날아가는 중에 다른 화면으로 가고 그 저장이 끊기면 마지막 입력이 경고 없이 사라졌다(#5).
  test "저장 중에 다른 화면으로 가고 그 저장이 끊겨도, 떠난 뒤 한 번 더 보내 글을 지킨다" do
    draft = Report.create!(user: @student, classroom: @classroom, book: @book, book_title: @book.title,
                           body: "쓰다 만 글이에요.", input_mode: :keyboard, ai_status: :pending)
    login_via_browser
    visit edit_report_path(draft)
    fail_first_autosave_after(1500)

    find("#report_body_field").send_keys(" 떠나기 직전에 쓴 글")
    assert_selector "[data-report-autosave-target='status']", text: "저장 중…", wait: SAVE_WAIT
    click_on "취소"
    assert_current_path reports_path

    eventually { draft.reload.body == "쓰다 만 글이에요. 떠나기 직전에 쓴 글" }
    # 떠난 뒤에는 타이머로 다시 보내지 않고, 떠나는 순간용 요청(keepalive)으로 딱 한 번 보낸다.
    assert_equal [ false, true ], evaluate_script("window.__autosaveKeepalive")
  rescue Selenium::WebDriver::Error::WebDriverError => e
    skip "headless chrome(chromedriver)를 사용할 수 없어 시스템 테스트를 건너뜁니다: #{e.message}"
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
    skip "headless chrome(chromedriver)를 사용할 수 없어 시스템 테스트를 건너뜁니다: #{e.message}"
  end


  # --- 3차 코드 리뷰(b67c678) 후속: 되돌려도 통과하던 브라우저 계약 ---

  # 떠난 뒤 실패한 저장은 한 번만 다시 보낸다. 재시도 타이머까지 걸면 떠난 화면의 옛 글을 몇 초 뒤 또 보낸다.
  test "떠난 뒤에는 실패해도 재시도 타이머를 걸지 않는다 — 딱 한 번만 다시 보낸다" do
    draft = Report.create!(user: @student, classroom: @classroom, book: @book, book_title: @book.title,
                           body: "쓰다 만 글이에요.", input_mode: :keyboard, ai_status: :pending)
    login_via_browser
    visit edit_report_path(draft)
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
    click_on "취소"
    assert_current_path reports_path

    eventually { evaluate_script("window.__autosaveKeepalive.length") == 2 } # 떠난 뒤의 한 번까지 끊겼다
    sleep 1.5 # 두 번째 실패가 처리될 시간
    assert_equal [], evaluate_script("window.__longTimers"), "떠난 화면이 재시도 타이머를 걸면 옛 글을 몇 초 뒤 또 보낸다"
    assert_equal 2, evaluate_script("window.__autosaveKeepalive.length")
  rescue Selenium::WebDriver::Error::WebDriverError => e
    skip "headless chrome(chromedriver)를 사용할 수 없어 시스템 테스트를 건너뜁니다: #{e.message}"
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
    skip "headless chrome(chromedriver)를 사용할 수 없어 시스템 테스트를 건너뜁니다: #{e.message}"
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
    skip "headless chrome(chromedriver)를 사용할 수 없어 시스템 테스트를 건너뜁니다: #{e.message}"
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
    skip "headless chrome(chromedriver)를 사용할 수 없어 시스템 테스트를 건너뜁니다: #{e.message}"
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
    skip "headless chrome(chromedriver)를 사용할 수 없어 시스템 테스트를 건너뜁니다: #{e.message}"
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
    skip "headless chrome(chromedriver)를 사용할 수 없어 시스템 테스트를 건너뜁니다: #{e.message}"
  end

  private

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
