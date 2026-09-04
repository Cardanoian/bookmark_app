require "test_helper"

# 새 독후감 쓰기 진입 플로우 — 책 고르기 → 모드 선택 → (직접 쓰기 / 사진으로 쓰기).
# GET /reports/new 가 input_mode 우선 4분기로 스텝 뷰를 가른다(계획 §5):
#   input_mode=ocr      → _photo_capture
#   input_mode=keyboard → _form (+ hidden report[input_mode])
#   report[book_*] 존재 → _mode_chooser (고른 책을 두 모드 링크로 전달)
#   그 외(빈 값 포함)   → _book_chooser (진입 스텝)
class ReportInputModeTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @school = School.create!(name: "입력모드학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @student = User.create!(school: @school, classroom: @classroom, name: "입력모드학생", password: "password",
                            ai_consent: true, privacy_consent_at: Time.current)
    @book = Book.create!(title: "은하철도의 밤", author: "미야자와 겐지", category: :recommended)
  end

  # AC1 — 파라미터 없이 진입하면 첫 스텝은 "책 고르기"다. 책 검색 필드와 "다음" 버튼이 있고,
  # 모드 선택 카드(input_mode 링크)는 아직 없다.
  test "new without params renders the book chooser entry step" do
    login_as @student

    get new_report_path
    assert_response :success
    assert_select "input[name=?]", "report[book_title]", 1
    assert_select "input[type=submit][value=?]", "다음", 1
    assert_select "a[href*=?]", "input_mode=keyboard", 0
    assert_select "textarea#report_body_field", 0
  end

  # 책을 고르지 않고 넘어가는 두 경로(엔터·"다음" 클릭)를 막되, 자유 제목 폴백은 **명시 버튼**으로
  # 남긴다 — 카탈로그·네이버에 없는 책도 독후감을 쓸 수 있어야 한다(mode: "fallback" 은 의도된 설계).
  # 게이트 자체는 JS 가 걸므로 여기서는 그 마크업 계약을 고정한다.
  test "book chooser gates progress on an actual selection but keeps an explicit free-title path" do
    login_as @student
    get new_report_path
    assert_response :success

    assert_select "div[data-controller='book-chooser']", 1
    assert_select "input[type=submit][data-book-chooser-target='next'][value=?]", "다음", 1
    assert_select "input[type=submit][data-book-chooser-target='fallback']", 1
    # 검색창에서 엔터가 폼을 제출하지 않게 하는 opt-in 이 이 화면에만 붙는다.
    assert_select "input[data-action*='keydown.enter->book-search#submitSearch']", 1
    # 버튼은 활성으로 렌더된다 — 비활성화는 connect() 가 한다(JS 없으면 기존 동작 유지).
    assert_select "input[type=submit][disabled]", 0
  end

  # 이 화면 말고 다른 자동완성 화면에는 엔터 차단이 붙지 않는다(엔터가 정상 동선인 곳들).
  test "the enter guard is opt-in and does not leak into the report form" do
    login_as @student

    get new_report_path(input_mode: :keyboard, report: { book_title: "어떤 책" })
    assert_response :success
    assert_select "input[data-action*='book-search#submitSearch']", 0
  end

  # 빈 문자열 파라미터는 present? 로 걸러져 mode_chooser 가 아니라 book_chooser 로 낙하한다.
  test "blank book_title falls through to the book chooser (not the mode chooser)" do
    login_as @student

    get new_report_path(report: { book_title: "" })
    assert_response :success
    assert_select "input[type=submit][value=?]", "다음", 1
    assert_select "a[href*=?]", "input_mode=keyboard", 0
  end

  # AC1/AC5 — 책을 고르면(book_title 존재) 모드 선택 카드가 뜨고, 두 모드 링크는 고른 책을
  # 그대로 실어 다음 스텝으로 넘긴다. "다음" 버튼(book_chooser)은 더 이상 없다.
  test "choosing a book renders the mode chooser carrying the book forward" do
    login_as @student

    with_gemini_available do
      get new_report_path(report: { book_title: @book.title })
    end
    assert_response :success
    assert_select "input[type=submit][value=?]", "다음", 0

    # 두 모드 링크가 고른 책(book_title)을 실어 전달한다. book_id/remote_isbn 미전달이므로 nil 로 일치.
    # 직접 쓰기(keyboard) 링크는 안내형 작성 진입을 위해 guided=1 도 함께 싣는다(§1a).
    keyboard_href = new_report_path(input_mode: :keyboard, guided: 1,
      report: { book_id: nil, book_title: @book.title, remote_isbn: nil })
    ocr_href = new_report_path(input_mode: :ocr,
      report: { book_id: nil, book_title: @book.title, remote_isbn: nil })
    assert_select "a[href=?]", keyboard_href, 1
    assert_select "a[href=?]", ocr_href, 1
    # "책 다시 고르기"로 1스텝(book_chooser)으로 돌아갈 수 있다.
    assert_select "a[href=?]", new_report_path, text: "책 다시 고르기"
  end

  # OCR 키가 없으면 모드 선택에서 사진 카드는 링크가 아니라 비활성 카드로 표시된다.
  test "mode chooser disables the photo card when OCR is unavailable" do
    login_as @student

    get new_report_path(report: { book_title: @book.title })
    assert_response :success
    assert_select "a[href*=?]", "input_mode=keyboard", 1
    assert_select "a[href*=?]", "input_mode=ocr", 0
    assert_select "[aria-disabled='true']", 1
    assert_match "지금은 사진 입력을 쓸 수 없어요", response.body
  end

  # AC2 — 직접 쓰기 화면: 본문 textarea + 제출 + hidden report[input_mode](=keyboard),
  # 사진 위젯은 없다. hidden input_mode 는 create 검증 실패 재렌더 시 _form 분기를 복원한다.
  test "keyboard mode renders the compose form with a hidden input_mode field" do
    login_as @student

    get new_report_path(input_mode: :keyboard, report: { book_id: @book.id })
    assert_response :success
    assert_select "textarea#report_body_field", 1
    assert_select "input[name=?][value=?]", "report[input_mode]", "keyboard", 1
    # 제출 버튼 2개 — "제출하기"(첨삭 시작)와 "임시 저장"(제출 없이 초안으로만 저장).
    assert_select "input[type=submit][value=?]", "제출하기", 1
    assert_select "input[type=submit][name='save_draft']", 1
    assert_no_match(/name="ocr\[photo\]"/, response.body)
  end

  # AC2/AC3 — 사진으로 쓰기 화면: 책제목 자동완성(ocr 스코프) + 업로드 + canvas/preview,
  # 직접 작성 폼(본문 textarea)은 렌더되지 않는다.
  test "ocr mode renders the photo capture screen with book autocomplete" do
    login_as @student

    with_gemini_available do
      get new_report_path(input_mode: :ocr, report: { book_id: @book.id })
    end
    assert_response :success
    assert_match(/name="ocr\[photo\]"/, response.body)
    assert_select "input[name='ocr[book_title]']", 1
    assert_select "canvas", 1
    assert_select "textarea#report_body_field", 0
  end

  # AC5 — 고른 책이 사진 폼에도 프리필돼야 한다. 원격(네이버) 책은 book_id 가 없어(등록은 제출 시)
  # report.book=nil 이므로 title_value(=@report.book_title) 로 제목을 채우고, 로컬 책(book_id)은
  # selected_book(=report.book) 이 제목·표지를 채운다. keyboard _form 과의 프리필 비대칭 해소.
  test "photo capture prefills the chosen book title for both remote and local picks" do
    login_as @student

    # 원격 책: book_id 없음 + remote_isbn + book_title → title_value fallback 으로 제목 프리필.
    with_gemini_available do
      get new_report_path(input_mode: :ocr,
        report: { book_title: "원격으로 고른 책", remote_isbn: "9791234567896" })
    end
    assert_response :success
    assert_select "input[name='ocr[book_title]'][value=?]", "원격으로 고른 책", 1

    # 로컬 책: book_id → selected_book(report.book) 이 제목을 프리필(원격 title_value 보다 우선).
    with_gemini_available do
      get new_report_path(input_mode: :ocr, report: { book_id: @book.id })
    end
    assert_response :success
    assert_select "input[name='ocr[book_title]'][value=?]", @book.title, 1
  end

  # 결합 해제 회귀 — 학습 위저드 완료는 이제 input_mode=keyboard 를 명시해 넘긴다
  # (learn_controller.rb). 이 경로가 keyboard 폼으로 직행해 프리필 본문이 보존돼야 한다.
  test "learn handoff with input_mode keyboard routes straight to the compose form" do
    login_as @student

    get new_report_path(input_mode: :keyboard, report: { book_title: "책", body: "위저드가 채운 본문" })
    assert_response :success
    assert_select "textarea#report_body_field", text: /위저드가 채운 본문/
  end

  # 회귀 — input_mode 없이 book_title 만 실린 (구) 프리필은 이제 모드 선택 스텝으로 간다
  # (책 선택 → 모드 선택 순서 재구성). 본문은 keyboard 링크로 계속 이어진다.
  test "prefill without input_mode now lands on the mode chooser" do
    login_as @student

    get new_report_path(report: { book_title: "책", body: "위저드가 채운 본문" })
    assert_response :success
    assert_select "textarea#report_body_field", 0
    assert_select "a[href*=?]", "input_mode=keyboard", 1
  end

  # create 검증 실패 시 render :new 가 hidden report[input_mode]=keyboard 로 _form 을 재렌더한다
  # (book_chooser/mode_chooser 로 새지 않는다). Report 는 body presence 검증이 없어 실패는
  # book 참조 부재(book_reference_present)로 유도한다.
  test "failed create re-renders the compose form via the hidden input_mode" do
    login_as @student

    assert_no_difference "Report.count" do
      post reports_path, params: {
        report: { input_mode: "keyboard", book_id: "", book_title: "", body: "" }
      }
    end
    assert_response :unprocessable_entity
    assert_select "textarea#report_body_field", 1
    assert_select "input[name=?][value=?]", "report[input_mode]", "keyboard", 1
    assert_select "input[type=submit][value=?]", "다음", 0
  end

  # OcrJob 완료로 body 가 채워진 OCR 초안을 열면 compose(edit) 화면에 그 본문이 렌더된다.
  test "edit renders the OCR-filled body once the job has completed" do
    report = Report.create!(user: @student, classroom: @classroom, book_title: "사진 책", input_mode: :ocr)
    report.update!(body: "사진에서 읽어낸 본문", ai_status: :done)
    login_as @student

    get edit_report_path(report)
    assert_response :success
    assert_select "textarea#report_body_field", text: /사진에서 읽어낸 본문/
  end

  private

  # Minitest 6 에는 minitest/mock 이 없다. 원본 메서드를 보관했다가 복원한다(ocr_test.rb 관례).
  def with_gemini_available
    original = Ai::GeminiClient.method(:available?)
    Ai::GeminiClient.define_singleton_method(:available?) { true }
    yield
  ensure
    Ai::GeminiClient.define_singleton_method(:available?, original)
  end
end
