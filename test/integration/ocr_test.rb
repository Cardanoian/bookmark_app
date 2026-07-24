require "test_helper"

class OcrTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @school = School.create!(name: "OCR통합학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @student = User.create!(school: @school, classroom: @classroom, name: "OCR학생", password: "password",
                            ai_consent: true, privacy_consent_at: Time.current)
  end

  # P3.5 — 키 없음: 모드 선택 화면에서 사진 카드 비활성 + 서버에서 OCR 거부.
  # 모드 선택은 책을 고른 뒤(책 → 모드 순서) 도달하므로 book_title 을 실어 진입한다.
  test "the photo card is disabled and OCR is refused when the Gemini key is blank" do
    login_as @student

    get new_report_path(report: { book_title: "책" })
    assert_response :success
    assert_select "a[href=?]", new_report_path(input_mode: :ocr), count: 0
    assert_select "[aria-disabled='true']", 1
    assert_match "지금은 사진 입력을 쓸 수 없어요", response.body

    assert_no_enqueued_jobs(only: OcrJob) do
      post ocr_path, params: { ocr: { book_title: "책", photo: uploaded_photo } }
    end
    assert_redirected_to new_report_path
  end

  # P3.5 — 키 있음(스텁): OcrJob 예약 + compose(edit) 화면으로 redirect(§4.3).
  test "OCR enqueues a job and redirects to the compose screen when the key is available" do
    login_as @student

    with_gemini_available do
      assert_enqueued_with(job: OcrJob) do
        post ocr_path, params: { ocr: { book_title: "책", photo: uploaded_photo } }
      end
    end

    draft = @student.reports.order(:created_at).last
    assert_not_nil draft
    assert_redirected_to edit_report_path(draft)
  end

  private

  def uploaded_photo
    fixture_file_upload("handwriting.png", "image/png")
  end

  # Minitest 6 에는 minitest/mock 이 없다. 원본 메서드를 보관했다가 복원한다.
  def with_gemini_available
    original = Ai::GeminiClient.method(:available?)
    Ai::GeminiClient.define_singleton_method(:available?) { true }
    yield
  ensure
    Ai::GeminiClient.define_singleton_method(:available?, original)
  end
end
