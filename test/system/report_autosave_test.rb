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
    execute_script(<<~JS)
      window.__autosaveKeepalive = []
      const original = window.fetch
      window.fetch = (input, init = {}) => {
        if (new Headers(init.headers || {}).get("Accept") === "application/json") window.__autosaveKeepalive.push(!!init.keepalive)
        return original(input, init)
      }
    JS
  end

  def recorded_keepalive_flags
    evaluate_script("window.__autosaveKeepalive")
  end

  # 자동 저장(Accept: application/json)의 **응답만** 늦춘다 — 요청은 곧바로 서버에 닿아 초안이 생기고,
  # 브라우저는 그 사실을 늦게 안다(느린 학교 망). 이 사이에 제출이 기다리지 않으면 create 로 한 편이
  # 더 생긴다. 요청을 늦추면 제출이 먼저 끝나 버려 이 위험을 못 본다. Turbo 의 제출(HTML)은 그대로 둔다.
  def delay_autosave_requests(ms)
    execute_script(<<~JS, ms)
      const delay = arguments[0]
      const original = window.fetch
      window.fetch = (input, init = {}) => {
        const json = new Headers(init.headers || {}).get("Accept") === "application/json"
        const request = original(input, init)
        return json ? request.then((response) => new Promise((resolve) => setTimeout(() => resolve(response), delay))) : request
      }
    JS
  end

  # 자동 저장 요청에 서버 대신 정해 둔 응답을 돌려준다.
  def answer_autosave_with(status:, body:)
    execute_script(<<~JS, status, body.to_json)
      const [status, body] = [arguments[0], arguments[1]]
      const original = window.fetch
      window.fetch = (input, init = {}) => {
        const json = new Headers(init.headers || {}).get("Accept") === "application/json"
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
