require_relative "application_system_test_case"

# report-review-gate E2E: 학생 제출 → "선생님 확인 중" → 교사 승인 → 첨삭 노출. 한 브라우저
# 세션 안에서 앱의 실제 로그아웃 버튼으로 학생↔교사를 오가며 검증한다(Capybara
# `using_session` 두 세션 설계는 chromedriver 가 아예 없는 환경에서 driver 최초 접근 시점의
# 예외가 Capybara.using_session 의 ensure 절에서 다른 예외로 가려지는 문제가 있어 회피했다 —
# 라이브(무새로고침) 반영 자체는 integration 테스트(assert_turbo_stream_broadcasts)가 커버한다).
# headless chrome(chromedriver)이 없는 환경에서는 브라우저 기동 시점에 실패하므로, 그 경우
# 이 스펙 전체를 건너뛴다(기존 관례, reports_guided_compose_test.rb 참고).
class ReportReviewGateSystemTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    @school = School.create!(name: "게이트시스템학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @teacher = User.create!(school: @school, classroom: @classroom, name: "게이트시스템담임", role: :teacher,
      email: "gate-system-teacher@test.local", password: "password")
    @classroom.update!(teacher: @teacher)
    @student = User.create!(school: @school, classroom: @classroom, name: "게이트시스템학생", password: "password")
  end

  test "제출 후 선생님 확인 중이다가 교사 승인 후에 첨삭이 학생 화면에 드러난다" do
    login_student_via_browser
    visit new_report_path(input_mode: :keyboard)
    fill_in "책 제목", with: "긴긴밤"
    fill_in "report_body_field",
      with: "나는 이 책을 읽고 우리의 삶과 나의 경험을 떠올리며 감동을 느꼈다. 스스로 반성하고 다짐했다."

    perform_enqueued_jobs do
      click_on "제출하기"
    end

    # ai_status: done 이지만 reviewed: false 인 대기 상태 — 첨삭 텍스트는 아직 숨겨져 있어야 한다.
    assert_text "선생님 확인 중"
    assert_no_text "선생님의 5축 첨삭"

    report = @student.reports.order(:created_at).last
    assert report.reload.done?, "AI 첨삭(규칙기반 폴백)이 완료돼야 승인 가능하다"

    click_on "로그아웃"
    login_teacher_via_browser
    visit teacher_review_path(report)
    click_on "승인"

    click_on "로그아웃"
    login_student_via_browser
    visit report_path(report)

    assert_text "확인 완료"
    assert_text "선생님의 5축 첨삭"
  rescue Selenium::WebDriver::Error::WebDriverError => e
    skip "headless chrome(chromedriver)를 사용할 수 없어 시스템 테스트를 건너뜁니다: #{e.message}"
  end

  private

  def login_student_via_browser
    visit student_login_path
    fill_in "학교 이름으로 찾기", with: @school.name
    find("li button", text: @school.name).click
    assert_selector "#classroom_id option", text: @classroom.label
    select @classroom.label, from: "classroom_id"
    fill_in "이름", with: @student.name
    fill_in "비밀번호", with: "password"
    click_button "로그인"
  end

  def login_teacher_via_browser
    visit staff_login_path
    fill_in "이메일", with: @teacher.email
    fill_in "비밀번호", with: "password"
    click_button "로그인"
  end
end
