require "test_helper"

class ReportTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "독후감초등학교")
    @classroom = Classroom.create!(school: @school, grade: 3, class_no: 1)
    @user = User.create!(school: @school, classroom: @classroom, name: "독후감학생", password: "password")
    @book = Book.create!(title: "마당을 나온 암탉")
  end

  test "input_mode enum defines three values" do
    assert_equal({ "keyboard" => 0, "wongoji" => 1, "ocr" => 2 }, Report.input_modes)
  end

  test "ai_status enum defines four values" do
    assert_equal({ "pending" => 0, "processing" => 1, "done" => 2, "failed" => 3 }, Report.ai_statuses)
  end

  test "defaults to keyboard input and pending ai_status" do
    report = build_report
    assert report.keyboard?
    assert report.pending?
  end

  test "is valid with a book reference" do
    assert build_report(book: @book, book_title: nil).valid?
  end

  test "is valid with a book_title only" do
    assert build_report(book: nil, book_title: "책 제목만").valid?
  end

  test "requires either a book or a book_title" do
    report = build_report(book: nil, book_title: nil)
    assert_not report.valid?
  end

  test "level must be A, B, or C when present" do
    assert build_report(level: "A").valid?
    assert build_report(level: nil).valid?
    assert_not build_report(level: "D").valid?
  end

  test "self-referential revision_of association works" do
    original = build_report(book_title: "원본").tap(&:save!)
    revision = build_report(book_title: "고쳐쓰기", revision_of: original)
    assert revision.save
    assert_equal original, revision.revision_of
    assert_includes original.revisions, revision
  end

  test "accepts an image photo attachment" do
    report = build_report(book_title: "사진 있는 글")
    report.photo.attach(io: StringIO.new("fake-image-bytes"), filename: "cover.png", content_type: "image/png")
    assert report.valid?, report.errors.full_messages.to_sentence
  end

  test "rejects a non-image content type for the photo attachment" do
    report = build_report(book_title: "잘못된 첨부")
    report.photo.attach(io: StringIO.new("plain text"), filename: "note.txt", content_type: "text/plain")
    assert_not report.valid?
    assert report.errors[:photo].any?
  end

  test "rejects a non-audio content type for the audio attachment" do
    report = build_report(book_title: "잘못된 오디오")
    report.audio.attach(io: StringIO.new("not audio"), filename: "note.txt", content_type: "text/plain")
    assert_not report.valid?
    assert report.errors[:audio].any?
  end

  private

  def build_report(attrs = {})
    Report.new({ user: @user, classroom: @classroom, book_title: "기본 제목" }.merge(attrs))
  end
end
