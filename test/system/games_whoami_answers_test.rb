require_relative "application_system_test_case"

# 나는 누구게? 답안은 제출 전까지 브라우저 DOM에만 있다. 다른 문항의 힌트를 공개해도 전체 페이지를
# 다시 그리지 않고 해당 힌트 카드만 갱신해, 이미 입력한 모든 답안이 유지되는지 실제 브라우저로 검증한다.
class GamesWhoamiAnswersTest < ApplicationSystemTestCase
  setup do
    @school = School.create!(name: "누구게시스템학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @student = User.create!(school: @school, classroom: @classroom, name: "누구게학생", password: "password",
      nickname: "누구게학생닉", ranking_opted_in: true)
    @book = Book.create!(title: "누구게책", author: "김작가", category: :recommended)
    CuratedQuiz.create!(book: @book, content_axis: :hint_reveal, payload: [
      { "answer" => "주인공", "hints" => [ "이야기의 중심인물이에요", "모험을 떠나요" ], "difficulty" => 1 },
      { "answer" => "친구", "hints" => [ "주인공을 도와줘요", "함께 길을 걸어요" ], "difficulty" => 1 },
      { "answer" => "선생님", "hints" => [ "배움을 이끌어 줘요", "학교에서 만나요" ], "difficulty" => 1 }
    ])
  end

  test "다른 문항의 힌트를 열어도 작성 중인 답안이 유지된다" do
    login_via_browser
    visit games_whoami_play_path(book_id: @book.id)
    assert_current_path %r{\A/games/whoami/\d+\z}

    attempt = @student.quiz_attempts.order(:id).last
    first, second, third = attempt.quiz.quiz_questions.to_a
    fill_answer(first, "주인공")
    fill_answer(third, "선생님")

    hint_card_id = ActionView::RecordIdentifier.dom_id(second, :hint_card)
    within "##{hint_card_id}" do
      click_button "힌트 더 보기"
      assert_text "주인공을 도와줘요"
    end

    assert_equal "주인공", answer_field(first).value
    assert_equal "선생님", answer_field(third).value
    assert_equal 1, attempt.reload.revealed_count(second)
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

  def answer_field(question)
    find("input[name='answers[#{question.id}]']")
  end

  def fill_answer(question, value)
    answer_field(question).fill_in(with: value)
  end
end
