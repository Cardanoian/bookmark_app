require "test_helper"

# 손글씨 사진은 촬영 정보(촬영 일시·기기·위치)를 지운 사본만 저장한다(PhotoSanitizer, 2026-11-11). 업로드 화면의
# 브라우저 압축은 압축한 파일이 더 크거나 사진을 열지 못하면 원본을 그대로 보내므로 서버가 지운다.
class OcrPhotoSanitizingTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @school = School.create!(name: "사진정리학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @student = User.create!(school: @school, classroom: @classroom, name: "사진정리학생", password: "password",
                            ai_consent: true, privacy_consent_at: Time.current)
  end

  test "stores the photo without the camera information" do
    require_libvips!
    login_as @student

    with_ocr_available do
      assert_enqueued_with(job: OcrJob) do
        post ocr_path, params: { ocr: { book_title: "책", photo: photo_with_exif } }
      end
    end

    draft = @student.reports.order(:created_at).last
    assert_redirected_to edit_report_path(draft)
    bytes = draft.photo.blob.download
    assert_nil bytes.index("Exif\x00\x00".b), "저장된 사진에 EXIF 가 남아 있으면 안 된다"
    assert_empty Vips::Image.new_from_buffer(bytes, "").get_fields.grep(/\A(exif|xmp|iptc)-/)
    assert_equal "photo.jpg", draft.photo.blob.filename.to_s, "촬영 일시가 든 파일 이름도 남기지 않는다"
    assert_equal "image/jpeg", draft.photo.blob.content_type
  end

  # 지우지 못한 사진은 원본을 남기지 않는다 — 초안·첨부를 만들기 전에 돌려보낸다. 테스트 사진은 진짜 이미지가
  # 아니라 libvips 가 있어도 없어도(LoadError) 이 길을 탄다.
  test "a photo that cannot be cleaned is turned away before anything is stored" do
    login_as @student

    with_ocr_available do
      assert_no_difference [ "Report.count", "ActiveStorage::Blob.count" ] do
        assert_no_enqueued_jobs(only: OcrJob) do
          post ocr_path, params: { ocr: { book_title: "책", photo: fixture_file_upload("handwriting.png", "image/png") } }
        end
      end
    end

    assert_redirected_to new_report_path(input_mode: :ocr)
    assert_equal "사진을 열지 못했어요. 다시 찍어서 올려 주세요.", flash[:alert]
  end

  # 너무 큰 사진은 같은 파일을 다시 올려도 같으니, 카메라로 다시 찍게(앱 화면이 줄여 보낸다) 안내를 나눈다.
  test "a photo over the size limit gets its own message" do
    login_as @student
    big = Rack::Test::UploadedFile.new(StringIO.new("x" * (Report::IMAGE_MAX_BYTES + 1)), "image/jpeg", true,
                                       original_filename: "IMG_0001.jpg")

    with_ocr_available do
      assert_no_difference "Report.count" do
        post ocr_path, params: { ocr: { book_title: "책", photo: big } }
      end
    end

    assert_redirected_to new_report_path(input_mode: :ocr)
    assert_equal "사진이 너무 커요. 카메라로 다시 찍어서 올려 주세요.", flash[:alert]
  end

  # direct upload 로 미리 올려 둔 blob 의 signed id 를 사진 칸에 넣어도 정리를 비켜 붙지 않는다.
  test "a signed blob id in the photo field is refused" do
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("raw"), filename: "IMG_1.jpg", content_type: "image/jpeg")
    login_as @student

    with_ocr_available do
      assert_no_difference "Report.count" do
        post ocr_path, params: { ocr: { book_title: "책", photo: blob.signed_id } }
      end
    end

    assert_redirected_to new_report_path(input_mode: :ocr)
    assert_not ActiveStorage::Attachment.exists?(blob_id: blob.id)
  end

  # 사진은 OcrController 로만 받는다 — 독후감 저장 경로로 보낸 첨부(report[photo]·그림 칸에 넣은 사진·음성)는
  # 붙지 않는다. 받으면 정리를 비켜 원본이 저장된다.
  test "the report form does not take attachments" do
    login_as @student

    assert_difference "Report.count", 1 do
      post reports_path, params: {
        report: { book_title: "책", body: "나는 이 책을 읽었다.", input_mode: "ocr",
                  photo: fixture_file_upload("handwriting.png", "image/png"),
                  drawing: fixture_file_upload("handwriting.png", "image/png"),
                  audio: fixture_file_upload("handwriting.png", "image/png") }
      }
    end

    report = @student.reports.order(:created_at).last
    assert_not report.photo.attached?
    assert_not report.drawing.attached?
    assert_not report.audio.attached?
  end

  private

  def photo_with_exif
    Rack::Test::UploadedFile.new(StringIO.new(jpeg_with_exif(orientation: 6)), "image/jpeg", true,
                                 original_filename: "IMG_20261111_093000.jpg")
  end

  # Minitest 6 에는 minitest/mock 이 없다. 원본 메서드를 보관했다가 복원한다(ocr_test.rb 관례).
  def with_ocr_available
    original = Ai::ClaudeClient.method(:available?)
    Ai::ClaudeClient.define_singleton_method(:available?) { true }
    yield
  ensure
    Ai::ClaudeClient.define_singleton_method(:available?, original)
  end
end
