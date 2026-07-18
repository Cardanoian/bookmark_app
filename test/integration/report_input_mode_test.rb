require "test_helper"

# 새 독후감 쓰기 — 입력 모드 선택 화면(chooser/keyboard/ocr 3분기) 통합 테스트.
# GET /reports/new 가 params[:input_mode](+report 프리필)로 화면을 갈라 렌더한다(계획 §4.4).
class ReportInputModeTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @school = School.create!(name: "입력모드학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @student = User.create!(school: @school, classroom: @classroom, name: "입력모드학생", password: "password")
  end

  # AC1 — 파라미터 없이 진입하면 모드 선택 카드. 직접 쓰기는 무키에서도 링크,
  # 사진으로 쓰기는 Gemini 키가 있을 때만 링크가 된다.
  test "new without input_mode renders the mode chooser with both cards" do
    login_as @student

    get new_report_path
    assert_response :success
    assert_select "a[href=?]", new_report_path(input_mode: :keyboard), 1

    with_gemini_available do
      get new_report_path
      assert_response :success
      assert_select "a[href=?]", new_report_path(input_mode: :ocr), 1
    end
  end

  # AC7 — 키 없으면 사진 카드가 링크가 아니라 비활성 카드로 표시된다.
  test "mode chooser disables the photo card when OCR is unavailable" do
    login_as @student

    get new_report_path
    assert_response :success
    assert_select "a[href=?]", new_report_path(input_mode: :ocr), 0
    assert_select "[aria-disabled='true']", 1
    assert_match "지금은 사진 입력을 쓸 수 없어요", response.body
  end

  # AC2 — 직접 쓰기 화면: 본문 textarea + 제출, 사진 위젯 없음.
  test "keyboard mode renders the compose form without the photo widget" do
    login_as @student

    get new_report_path(input_mode: :keyboard)
    assert_response :success
    assert_select "textarea#report_body_field", 1
    assert_select "input[type=submit]", 1
    assert_no_match(/name="ocr\[photo\]"/, response.body)
  end

  # AC3 — 사진으로 쓰기 화면: 책제목 자동완성 + 업로드(카메라/갤러리) + canvas/preview,
  # 직접 작성 폼(본문 textarea)은 렌더되지 않는다.
  test "ocr mode renders the photo capture screen with book autocomplete" do
    login_as @student

    with_gemini_available do
      get new_report_path(input_mode: :ocr)
    end
    assert_response :success
    assert_match(/name="ocr\[photo\]"/, response.body)
    assert_select "input[name='ocr[book_title]']", 1
    assert_select "canvas", 1
    assert_select "textarea#report_body_field", 0
  end

  # C1 회귀 — 학습 위저드 완료는 input_mode 없이 report 파라미터만 실어 온다
  # (learn_controller.rb:77). 이 경로가 keyboard 폼으로 직행해 프리필이 보존돼야 한다.
  test "prefilled report params route straight to the keyboard form" do
    login_as @student

    get new_report_path(report: { book_title: "책", body: "위저드가 채운 본문" })
    assert_response :success
    assert_select "textarea#report_body_field", text: /위저드가 채운 본문/
  end

  # AC4 — OcrJob 완료로 body 가 채워진 OCR 초안을 열면 compose(edit) 화면에 그 본문이 렌더된다.
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
