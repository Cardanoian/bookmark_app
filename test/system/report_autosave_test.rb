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
    # "질문 없이 바로 쓰기"는 새 빈 글이 아니라 이 초안으로 간다.
    assert_equal edit_report_path(draft), URI(find("a[data-report-guide-target='skipLink']")[:href]).path

    click_on "초안 만들기"
    click_on "제출하기"
    assert_current_path report_path(draft)
    assert_equal 1, @student.reports.count
    assert draft.reload.submitted?
  rescue Selenium::WebDriver::Error::WebDriverError => e
    skip "headless chrome(chromedriver)를 사용할 수 없어 시스템 테스트를 건너뜁니다: #{e.message}"
  end

  private

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
