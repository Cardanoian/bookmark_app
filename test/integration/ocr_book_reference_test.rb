require "test_helper"

# 도서 참조 가드(계획 §4.3, 결함②) — 거부 검사가 draft 생성(create!) 이전에 배치돼
# book_id/book_title 이 모두 없으면 book_reference_present 실패로 인한 RecordInvalid
# 500 없이 조기 거부하고, 가짜 "사진 독후감" placeholder 없이 실제 제목으로 draft 가 태어난다.
class OcrBookReferenceTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @school = School.create!(name: "도서가드학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @student = User.create!(school: @school, classroom: @classroom, name: "도서가드학생", password: "password")
  end

  # AC6 — book_id·book_title 모두 공백이면 draft 를 만들기 전에 거부하고 500 이 아니다.
  test "rejects an upload with no book reference before creating a draft" do
    login_as @student

    with_gemini_available do
      assert_no_difference("Report.count") do
        assert_no_enqueued_jobs(only: OcrJob) do
          post ocr_path, params: { ocr: { book_id: "", book_title: "", photo: uploaded_photo } }
        end
      end
    end

    assert_redirected_to new_report_path(input_mode: :ocr)
  end

  # AC6 — book_title 이 있으면 그 실제 제목으로 draft 가 생성된다("사진 독후감" 아님).
  test "a book title creates a draft with the real title, not a placeholder" do
    login_as @student

    with_gemini_available do
      assert_enqueued_with(job: OcrJob) do
        post ocr_path, params: { ocr: { book_title: "어린왕자", photo: uploaded_photo } }
      end
    end

    draft = @student.reports.order(:created_at).last
    assert_not_nil draft
    assert_equal "어린왕자", draft.book_title
    assert_not_equal "사진 독후감", draft.book_title
  end

  private

  def uploaded_photo
    fixture_file_upload("handwriting.png", "image/png")
  end

  # Minitest 6 에는 minitest/mock 이 없다. 원본 메서드를 보관했다가 복원한다(ocr_test.rb 관례).
  def with_gemini_available
    original = Ai::GeminiClient.method(:available?)
    Ai::GeminiClient.define_singleton_method(:available?) { true }
    yield
  ensure
    Ai::GeminiClient.define_singleton_method(:available?, original)
  end
end
