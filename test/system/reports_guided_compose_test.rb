require_relative "application_system_test_case"

# 안내형 독후감 작성(guided compose, §1a) E2E — 질문에 답하고 "초안 만들기"를 누르면
# 답변이 이어붙어 제출 폼의 본문에 채워지고, 그대로 제출하면 독후감이 만들어지는지 확인한다.
# headless chrome(chromedriver)이 없는 환경에서는 브라우저 기동 시점에 실패하므로, 그 경우
# 이 스펙 전체를 건너뛴다(§ 지시: 드라이버 없을 수 있으니 방어).
class ReportsGuidedComposeTest < ApplicationSystemTestCase
  setup do
    @school = School.create!(name: "안내형작성시스템학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @teacher = User.create!(school: @school, classroom: @classroom, name: "시스템담임", role: :teacher, password: "password")
    @classroom.update!(teacher: @teacher)
    # 닉네임·랭킹 참여를 미리 정해 둔다. 비워 두면 `require_student_ranking_profile` 게이트가
    # 로그인 직후 모든 화면을 `ranking_preferences#edit` 로 되돌려 본 시나리오에 닿지 못한다
    # (`login_as(onboarded: true)` 가 integration 테스트에 해 주는 일의 브라우저 판본).
    @student = User.create!(school: @school, classroom: @classroom, name: "시스템학생", password: "password",
      nickname: "시스템학생닉", ranking_opted_in: true)
    @book = Book.create!(title: "긴긴밤", author: "루리", publisher: "문학동네", category: :recommended)
  end

  test "질문에 답하고 초안 만들기를 누르면 답변이 본문에 이어붙어 제출된다" do
    login_via_browser
    visit new_report_path(input_mode: :keyboard, guided: 1, report: { book_id: @book.id })
    assert_selector "div[data-controller='report-guide']"

    answers = all("textarea[data-report-guide-target='answer']")
    assert answers.size >= 3, "질문형 화면이면 답변 textarea 가 3개 이상이어야 한다"

    sample_texts = [ "책을 읽게 된 까닭을 적었어요.", "가장 기억에 남는 장면을 적었어요.", "내 삶과 연결해 느낀 점을 적었어요." ]
    answers.first(3).each_with_index { |field, index| field.fill_in with: sample_texts[index] }

    click_on "초안 만들기"

    body_field = find("#report_body_field", visible: :all)
    assert_equal sample_texts.join("\n\n"), body_field.value

    click_on "제출하기"

    assert_current_path %r{\A/reports/\d+\z}
    assert_text "긴긴밤"
  rescue Selenium::WebDriver::Error::WebDriverError => e
    skip "headless chrome(chromedriver)를 사용할 수 없어 시스템 테스트를 건너뜁니다: #{e.message}"
  end

  private

  # 학생 로그인 표면(학교 검색→선택→학급→이름·비밀번호)을 실제 브라우저로 진행한다.
  # chromedriver 가 없으면 최초 visit 에서 Selenium::WebDriver::Error::WebDriverError 가 나
  # 테스트 본문의 rescue 로 skip 된다.
  #
  # 마지막 `assert_current_path` 는 장식이 아니라 **필수 대기점**이다. `click_button` 은 Turbo
  # 폼 전송을 띄우기만 하고 곧바로 돌아오므로, 이어서 `visit` 하면 세션 쿠키가 심기기 전에 다음
  # 요청이 나가 `require_login` 이 로그인 인덱스로 되돌린다(뒤늦게 쿠키가 붙어 화면은 로그인한
  # 것처럼 보이는 탓에 원인 파악도 어렵다). 리다이렉트 도착지를 단언해 전송 완료를 기다린다.
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
