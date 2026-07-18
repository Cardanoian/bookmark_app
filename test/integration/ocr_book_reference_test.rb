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

  # 제출 시 원격 등록(캐시-우선·비차단) — remote_isbn + 빈 book_id 로 업로드하면 register 가
  # 캐시 메타로 Book 을 등록하고 draft.book_id 로 링크한 뒤 OcrJob 을 예약한다.
  test "remote_isbn 으로 원격 책을 등록해 draft.book_id 에 링크하고 OcrJob 을 예약한다" do
    login_as @student

    isbn = "9791111111111"
    with_gemini_available do
      with_memory_cache do
        Rails.cache.write("book_meta:#{isbn}", {
          id: nil, title: "OCR 원격책", author: "원격저자", publisher: "원격출판",
          thumbnail: "https://example.com/ocr.jpg", isbn: isbn, description: "설명"
        })

        assert_difference "Book.count", 1 do
          assert_enqueued_with(job: OcrJob) do
            post ocr_path, params: { ocr: { book_id: "", remote_isbn: isbn, photo: uploaded_photo } }
          end
        end
      end
    end

    draft = @student.reports.order(:created_at).last
    book = Book.find_by(isbn: isbn)
    assert_not_nil book, "remote_isbn 으로 Book 이 등록돼야 한다"
    assert_equal book.id, draft.book_id, "등록된 원격 책이 draft.book_id 로 링크돼야 한다"
  end

  # 등록 실패(무키·캐시 미스) + book_title 존재 → Book 미생성이지만 book_title 로 가드 통과.
  test "remote_isbn 등록 실패 시 Book 을 만들지 않고 book_title 로 통과한다" do
    login_as @student

    with_gemini_available do
      assert_no_difference "Book.count" do
        assert_enqueued_with(job: OcrJob) do
          post ocr_path, params: { ocr: { remote_isbn: "9780000000000", book_title: "무키 폴백책", photo: uploaded_photo } }
        end
      end
    end

    draft = @student.reports.order(:created_at).last
    assert_not_nil draft
    assert_nil draft.book_id, "등록 실패 시 book_id 는 공란"
    assert_equal "무키 폴백책", draft.book_title
  end

  # 등록 실패 + book_title 없음 → register nil 이 팬텀 통과를 만들지 않고 기존 가드로 거부된다.
  test "remote_isbn 등록 실패 + book_title 없음이면 draft 없이 거부한다" do
    login_as @student

    with_gemini_available do
      assert_no_difference("Report.count") do
        assert_no_difference("Book.count") do
          assert_no_enqueued_jobs(only: OcrJob) do
            post ocr_path, params: { ocr: { remote_isbn: "9780000000000", book_title: "", photo: uploaded_photo } }
          end
        end
      end
    end

    assert_redirected_to new_report_path(input_mode: :ocr)
  end

  private

  def uploaded_photo
    fixture_file_upload("handwriting.png", "image/png")
  end

  # test 환경 cache 는 null_store 라 캐시-우선 등록을 검증하려면 memory store 로 잠시 교체한다.
  def with_memory_cache
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    yield
  ensure
    Rails.cache = original
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
