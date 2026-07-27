require "test_helper"

# 아동 PII(손글씨) 바이트 서빙의 인가·유계·폴백 계약. 이 앱은 무인가 서명 URL 표면을 만들지 않고
# `ReportPhotosController` 가 요청마다 `ReportPolicy#show?` 를 강제한다(페이지 인가 미러).
class ReportPhotoServingTest < ActionDispatch::IntegrationTest
  # variant 처리는 libvips 에 의존해 호스트마다 가용성이 다르다. 실제 vips 호출 대신
  # `ActiveStorage::Attachment#variant` 를 가로채, 컨트롤러가 **요청한 유계 크기**와 **실패 폴백**을
  # libvips 유무와 무관하게 결정적으로 검증한다.
  VARIANT_BYTES = "STUBBED-VARIANT-BYTES"

  class FakeVariant
    def processed = self
    def download = VARIANT_BYTES
    def content_type = "image/png"
  end

  setup do
    @school = School.create!(name: "사진서빙학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @teacher = User.create!(school: @school, classroom: @classroom, name: "서빙담임", role: :teacher, password: "password")
    @classroom.update!(teacher: @teacher)

    @other_classroom = Classroom.create!(school: @school, grade: 5, class_no: 2)
    @other_teacher = User.create!(school: @school, classroom: @other_classroom, name: "타학급담임", role: :teacher, password: "password")
    @other_classroom.update!(teacher: @other_teacher)

    @student = User.create!(school: @school, classroom: @classroom, name: "서빙학생", password: "password")
    @other_student = User.create!(school: @school, classroom: @classroom, name: "남의학생", password: "password")
    @librarian = User.create!(school: @school, name: "사서", role: :librarian, password: "password", email: "lib@test.local")
    @school_admin = User.create!(school: @school, name: "교무", role: :school_admin, password: "password", email: "sa@test.local")

    @other_school = School.create!(name: "타학교")
    @other_school_classroom = Classroom.create!(school: @other_school, grade: 5, class_no: 1)
    @outsider = User.create!(school: @other_school, classroom: @other_school_classroom,
                             name: "타교학생", password: "password")

    @report = ocr_report_with_photo
  end

  # --- B1: 바이트 인가 = 페이지 인가(`ReportPolicy#show?`) 미러 ---

  test "the owning student, 담임, and same-school 사서·교무 all receive the photo" do
    [ @student, @teacher, @librarian, @school_admin ].each do |user|
      login_as user
      get report_photo_path(@report)
      assert_response :success, "#{user.role} should be allowed to fetch the photo"
      delete session_path
    end
  end

  test "another student, another classroom's teacher, and another school's student are forbidden" do
    [ @other_student, @other_teacher, @outsider ].each do |user|
      login_as user
      get report_photo_path(@report)
      assert_response :forbidden, "#{user.name} must not reach the photo bytes"
      delete session_path
    end
  end

  test "a logged out visitor is redirected to sign in instead of receiving bytes" do
    get report_photo_path(@report)
    assert_redirected_to new_session_path
  end

  # --- B2: 유계 variant(원본 바이트 미노출) ---

  test "the display path requests a 512px bounded variant and streams it" do
    login_as @student

    with_variant_seam do |calls|
      get report_photo_path(@report)
      assert_response :success
      assert_equal [ { resize_to_limit: [ 512, 512 ] } ], calls
      assert_equal VARIANT_BYTES, response.body
    end
  end

  test "the zoom path caps at 1600px rather than serving raw original bytes" do
    login_as @student

    with_variant_seam do |calls|
      get report_photo_path(@report, size: :original)
      assert_response :success
      assert_equal [ { resize_to_limit: [ 1600, 1600 ] } ], calls
      assert_equal VARIANT_BYTES, response.body
      assert_not_equal png_bytes.b, response.body.b
    end
  end

  test "variant failure degrades to the original instead of a 500" do
    login_as @student

    # StandardError(손상 이미지 등)와 LoadError(libvips 부재) 양쪽을 흡수해야 한다 —
    # LoadError 는 StandardError 가 아니라서 `rescue => e` 만으로는 500 이 난다.
    [ RuntimeError, LoadError ].each do |error_class|
      with_variant_seam(raise_error: error_class) do
        get report_photo_path(@report)
        assert_response :success, "#{error_class} should degrade to the original"
        assert_equal png_bytes.b, response.body.b
      end
    end
  end

  # --- B3: fail-closed — 폴백이 인가를 우회하지 않는다 ---

  test "an unauthorized request stays 403 even when variant processing would fail" do
    login_as @other_student

    with_variant_seam(raise_error: RuntimeError) do |calls|
      get report_photo_path(@report)
      assert_response :forbidden
      assert_empty calls, "authorization must reject before any variant work happens"
      assert_not_equal png_bytes.b, response.body.b
    end
  end

  test "a missing report propagates as 404 rather than being swallowed" do
    login_as @student
    get report_photo_path(id: Report.maximum(:id).to_i + 1)
    assert_response :not_found
  end

  test "an OCR report with no resolvable photo returns 404" do
    photoless = create_report(input_mode: :ocr)
    login_as @student

    get report_photo_path(photoless)
    assert_response :not_found
  end

  # --- G: 고쳐쓰기 승계 ---

  test "a multi-generation revision serves the root report's photo bytes" do
    second = revision_of(revision_of(@report))
    login_as @student

    with_variant_seam do
      get report_photo_path(second)
      assert_response :success
      assert_equal VARIANT_BYTES, response.body
    end
  end

  # --- B5: 조건부 GET ---

  test "the display path answers a repeat request with 304" do
    login_as @student

    with_variant_seam do
      get report_photo_path(@report)
      assert_response :success
      etag = response.headers["ETag"]
      assert_predicate etag.to_s, :present?

      get report_photo_path(@report), headers: { "HTTP_IF_NONE_MATCH" => etag }
      assert_response :not_modified
    end
  end

  private

  def with_variant_seam(raise_error: nil)
    calls = []
    original = ActiveStorage::Attachment.instance_method(:variant)
    ActiveStorage::Attachment.define_method(:variant) do |transformations|
      calls << transformations
      raise raise_error if raise_error

      FakeVariant.new
    end
    yield calls
  ensure
    ActiveStorage::Attachment.define_method(:variant, original)
  end

  def create_report(attrs = {})
    Report.create!({ user: @student, classroom: @classroom, book_title: "책", body: "본문",
                     ai_status: :done }.merge(attrs))
  end

  def ocr_report_with_photo
    create_report(input_mode: :ocr).tap do |report|
      report.photo.attach(io: StringIO.new(png_bytes), filename: "handwriting.png", content_type: "image/png")
    end
  end

  def revision_of(parent)
    Report.create!(user: parent.user, classroom: parent.classroom, book_title: parent.book_title,
                   body: "고쳐 쓴 본문", input_mode: parent.input_mode, revision_of: parent, ai_status: :done)
  end

  def png_bytes
    [ 137, 80, 78, 71, 13, 10, 26, 10 ].pack("C*") + ("\x00" * 64)
  end
end
