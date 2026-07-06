require "test_helper"

class OcrTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @school = School.create!(name: "OCR통합학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @student = User.create!(school: @school, classroom: @classroom, name: "OCR학생", password: "password")
  end

  # P3.5 — 키 없음: 폼에서 사진 모드 숨김 + 서버에서 OCR 거부.
  test "photo mode is hidden and OCR is refused when the Gemini key is blank" do
    login_as @student

    get new_report_path
    assert_response :success
    assert_match "키보드나 원고지로 입력해 주세요", response.body
    assert_no_match(/value="ocr"/, response.body)

    assert_no_enqueued_jobs(only: OcrJob) do
      post ocr_path, params: { ocr: { book_title: "책", photo: uploaded_photo } }
    end
    assert_redirected_to new_report_path
  end

  # P3.5 — 키 있음(스텁): OcrJob 예약 + Turbo Stream 응답.
  test "OCR enqueues a job and streams back when the key is available" do
    login_as @student

    with_gemini_available do
      assert_enqueued_with(job: OcrJob) do
        post ocr_path,
          params: { ocr: { book_title: "책", photo: uploaded_photo } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
    end

    assert_response :success
    assert_match "ocr_status", response.body
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

  def login_as(user)
    post session_path, params: {
      school_id: user.school_id, classroom_id: user.classroom_id,
      name: user.name, password: "password"
    }
  end
end
