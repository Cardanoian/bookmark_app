require "test_helper"

# 교사 검토 화면(teacher/reviews#show)의 OCR 사진 표시 — 담임이 손글씨 원본과 OCR 본문을
# 대조하며 검토할 수 있어야 한다. 학급 경계(타 학급 담임 403)는 회귀 검증으로 함께 잠근다.
class TeacherReviewPhotoTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "검토사진학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @teacher = User.create!(school: @school, classroom: @classroom, name: "사진담임", role: :teacher, password: "password")
    @classroom.update!(teacher: @teacher)

    @other_classroom = Classroom.create!(school: @school, grade: 5, class_no: 2)
    @other_teacher = User.create!(school: @school, classroom: @other_classroom, name: "타학급담임", role: :teacher, password: "password")
    @other_classroom.update!(teacher: @other_teacher)

    @student = User.create!(school: @school, classroom: @classroom, name: "사진학생", password: "password")
  end

  test "the 담임 sees the 512 photo and zoom link while reviewing an OCR report" do
    report = ocr_report_with_photo
    login_as @teacher

    get teacher_review_path(report)
    assert_response :success
    assert_select "img[src=?]", report_photo_path(report)
    assert_select "a[href=?]", report_photo_path(report, size: :original)
  end

  test "the review queue marks only reports with an OCR source photo" do
    ocr_report = ocr_report_with_photo
    keyboard_report = create_report(input_mode: :keyboard)
    login_as @teacher

    get teacher_reviews_path
    assert_response :success
    assert_select "#report_#{ocr_report.id} svg[aria-label='사진 원본 있음'][title='사진 원본 있음']", count: 1
    assert_select "#report_#{keyboard_report.id} svg[aria-label='사진 원본 있음']", count: 0
  end

  test "no photo section is rendered when reviewing a keyboard report" do
    report = create_report(input_mode: :keyboard)
    login_as @teacher

    get teacher_review_path(report)
    assert_response :success
    assert_select "img[src=?]", report_photo_path(report), count: 0
  end

  test "a non-담임 teacher is still forbidden from the review screen" do
    report = ocr_report_with_photo
    login_as @other_teacher

    get teacher_review_path(report)
    assert_response :forbidden
  end

  private

  def create_report(attrs = {})
    Report.create!({ user: @student, classroom: @classroom, book_title: "책", body: "본문",
                     ai_status: :done, avg: 3.0, level: "B", reviewed: false }.merge(attrs))
  end

  def ocr_report_with_photo
    create_report(input_mode: :ocr).tap do |report|
      report.photo.attach(io: StringIO.new(png_bytes), filename: "handwriting.png", content_type: "image/png")
    end
  end

  def png_bytes
    [ 137, 80, 78, 71, 13, 10, 26, 10 ].pack("C*") + ("\x00" * 64)
  end
end
