require "test_helper"

# 학생 상세(reports#show)의 OCR 사진 표시. 사진 섹션은 `_report_detail`(request 없는 방송에서도
# 렌더) **밖**의 show 스캐폴드에 있으므로, 방송 파티셜 계약을 건드리지 않고 검증한다.
class ReportPhotoDisplayTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "사진표시학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @student = User.create!(school: @school, classroom: @classroom, name: "사진학생", password: "password")
    @other_student = User.create!(school: @school, classroom: @classroom, name: "남의학생", password: "password")
  end

  test "a student sees the 512 photo and a zoom link on their own OCR report" do
    report = ocr_report_with_photo(@student)
    login_as @student

    get report_path(report)
    assert_response :success
    assert_select "img[src=?]", report_photo_path(report)
    assert_select "a[href=?]", report_photo_path(report, size: :original)
  end

  test "the photo section is absent from a keyboard report even if a photo is attached" do
    report = create_report(@student, input_mode: :keyboard)
    attach_photo(report)
    login_as @student

    get report_path(report)
    assert_response :success
    assert_select "img[src=?]", report_photo_path(report), count: 0
  end

  test "the photo section is absent from an OCR report without a photo" do
    report = create_report(@student, input_mode: :ocr)
    login_as @student

    get report_path(report)
    assert_response :success
    assert_select "img[src=?]", report_photo_path(report), count: 0
  end

  # 고쳐쓰기는 photo 를 승계하지 않는다 — 체인을 거슬러 root 원본 사진을 보여 줘야 한다.
  test "a multi-generation revision shows the root report's photo" do
    root = ocr_report_with_photo(@student)
    first = revision_of(root)
    second = revision_of(first)
    login_as @student

    get report_path(second)
    assert_response :success
    assert_select "img[src=?]", report_photo_path(second)
  end

  test "another student cannot open the report page at all" do
    report = ocr_report_with_photo(@student)
    login_as @other_student

    get report_path(report)
    assert_response :forbidden
  end

  private

  def create_report(user, attrs = {})
    Report.create!({ user: user, classroom: @classroom, book_title: "책", body: "본문",
                     ai_status: :done }.merge(attrs))
  end

  def ocr_report_with_photo(user)
    create_report(user, input_mode: :ocr).tap { |report| attach_photo(report) }
  end

  def attach_photo(report)
    report.photo.attach(io: StringIO.new(png_bytes), filename: "handwriting.png", content_type: "image/png")
    report
  end

  def revision_of(parent)
    Report.create!(user: parent.user, classroom: parent.classroom, book_title: parent.book_title,
                   body: "고쳐 쓴 본문", input_mode: parent.input_mode, revision_of: parent, ai_status: :done)
  end

  def png_bytes
    [ 137, 80, 78, 71, 13, 10, 26, 10 ].pack("C*") + ("\x00" * 64)
  end
end
