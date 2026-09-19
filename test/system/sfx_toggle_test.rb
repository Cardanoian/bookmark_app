require_relative "application_system_test_case"

# 보상 순간 효과음(2026-09-19) — 학생 헤더의 소리 켜기/끄기 버튼이 실제 브라우저에서 모듈(sfx)을 불러와
# 드러나고, 끈 상태를 기기(localStorage)에 기억해 새로고침 뒤에도 유지하는지 검증한다.
class SfxToggleTest < ApplicationSystemTestCase
  setup do
    @school = School.create!(name: "효과음시스템학교")
    @classroom = Classroom.create!(school: @school, grade: 3, class_no: 1)
    @student = User.create!(school: @school, classroom: @classroom, name: "효과음학생", password: "password",
      nickname: "효과음학생닉", ranking_opted_in: true)
  end

  test "소리 끄기를 누르면 기기에 기억되고 새로고침 뒤에도 꺼져 있다" do
    login_via_browser

    toggle = find("button[data-controller='sfx-toggle']")
    assert_equal "true", toggle["aria-pressed"], "기본은 켜짐"

    toggle.click
    assert_selector "button[data-controller='sfx-toggle'][aria-pressed='false'][aria-label='소리 켜기']"
    assert_equal "1", page.evaluate_script("localStorage.getItem('chaekgalpi:sfx-muted')")

    visit current_path
    assert_selector "button[data-controller='sfx-toggle'][aria-pressed='false']"

    find("button[data-controller='sfx-toggle']").click
    assert_selector "button[data-controller='sfx-toggle'][aria-pressed='true'][aria-label='소리 끄기']"
    assert_nil page.evaluate_script("localStorage.getItem('chaekgalpi:sfx-muted')")
  rescue Selenium::WebDriver::Error::WebDriverError => e
    skip "headless chrome(chromedriver)를 사용할 수 없어 시스템 테스트를 건너뜁니다: #{e.message}"
  end

  private

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
