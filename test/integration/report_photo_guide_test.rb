require "test_helper"

# 요구 1b — 사진으로 쓰기 전 자가점검 가이드(_photo_guide). 가이드 삽입이 기존 OCR 제출 폼을
# 깨뜨리지 않는지(회귀 없음) 함께 검증한다. Claude 키가 없으면 사진 단계 자체가 모드 선택에서
# 비활성 카드로 막히므로(ocr_test.rb 관례), 두 테스트 모두 with_claude_available 로 스텁한다.
class ReportPhotoGuideTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @school = School.create!(name: "가이드학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @student = User.create!(school: @school, classroom: @classroom, name: "가이드학생", password: "password",
                            ai_consent: true, privacy_consent_at: Time.current)
    @book = Book.create!(title: "가이드 테스트 책", author: "테스트저자", category: :recommended)
  end

  test "사진으로 쓰기 화면에 자가점검 가이드가 렌더된다" do
    login_as @student

    with_claude_available do
      get new_report_path(input_mode: :ocr, report: { book_id: @book.id })
    end
    assert_response :success

    assert_select "[data-controller='guide-modal']", 1
    # aria-modal 은 모달로 열릴 때만 guide-modal 컨트롤러가 부여한다(닫힘·JS 미로딩 인라인 카드
    # 상태에선 모달 시맨틱을 announce 하지 않음). 서버 마크업은 role=dialog + aria-labelledby 만 둔다.
    assert_select "[role='dialog'][aria-labelledby='photo-guide-title']", 1
    assert_select "[role='dialog'][aria-modal]", 0, "정적 마크업엔 aria-modal 이 없다(JS 가 열 때 부여)"
    assert_match "확인했어요", response.body
    assert_match "생각과 느낌", response.body

    guided = ReadingDomain.guided_questions(ReadingDomain.guided_band_for(@classroom.grade))
    assert_match guided[:ratio_hint], response.body
    assert_match guided[:spelling_tip], response.body
    guided[:questions].each do |q|
      assert_match q[:question], response.body
    end
  end

  test "가이드가 삽입돼도 OCR 사진 제출은 그대로 동작한다(회귀 없음)" do
    login_as @student

    with_claude_available do
      assert_enqueued_with(job: OcrJob) do
        post ocr_path, params: { ocr: { book_id: @book.id, photo: uploaded_photo } }
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

  # Minitest 6 에는 minitest/mock 이 없다. 원본 메서드를 보관했다가 복원한다(ocr_test.rb 관례).
  def with_claude_available
    original = Ai::ClaudeClient.method(:available?)
    Ai::ClaudeClient.define_singleton_method(:available?) { true }
    yield
  ensure
    Ai::ClaudeClient.define_singleton_method(:available?, original)
  end
end
