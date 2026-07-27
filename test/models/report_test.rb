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

  test "rejects an upload whose multipart content-type is spoofed as an image" do
    # 텍스트 파일이지만 멀티파트 Content-Type 을 image/png 로 위조 → 서버 재식별으로 거부.
    report = build_report(book_title: "스푸핑 첨부")
    report.photo.attach(io: StringIO.new("this is really plain text, not an image"),
                        filename: "evil.txt", content_type: "image/png")
    assert_not report.valid?, "위조된 content-type 은 통과하면 안 된다"
    assert report.errors[:photo].any?
  end

  test "accepts a genuine image identified by its magic bytes despite a mislabeled type" do
    report = build_report(book_title: "진짜 이미지")
    report.photo.attach(io: StringIO.new(png_bytes), filename: "cover.bin", content_type: "application/octet-stream")
    assert report.valid?, report.errors.full_messages.to_sentence
  end

  test "accepts a genuine audio file identified by its magic bytes" do
    report = build_report(book_title: "진짜 오디오")
    report.audio.attach(io: StringIO.new(wav_bytes), filename: "voice.dat", content_type: "application/octet-stream")
    assert report.valid?, report.errors.full_messages.to_sentence
  end

  test "a genuine image saves and uploads intact after server-side identification" do
    report = build_report(book_title: "저장되는 이미지")
    report.photo.attach(io: StringIO.new(png_bytes), filename: "cover.png", content_type: "image/png")
    assert report.save, report.errors.full_messages.to_sentence
    report.reload
    assert report.photo.attached?
    assert_equal png_bytes.bytesize, report.photo.blob.byte_size, "재식별 시 IO 를 읽어도 업로드가 잘리지 않는다"
  end

  # --- report-review-gate: feedback_visible?/student_feedback/broadcast_detail_refresh ---

  test "feedback_visible? requires both reviewed and a present rubric" do
    report = build_report(book_title: "게이트책")
    assert_not report.feedback_visible?, "미첨삭·미검토 상태는 노출 대상이 아니다"

    report.rubric = { content: 4, emotion: 4, life: 4, structure: 4, spelling: 4 }
    assert_not report.feedback_visible?, "reviewed 가 아니면 rubric 이 있어도 숨겨야 한다"

    report.reviewed = true
    assert report.feedback_visible?, "reviewed && rubric 이면 노출한다"
  end

  test "feedback_visible? is false when reviewed but rubric is blank" do
    report = build_report(book_title: "루브릭없음", reviewed: true, rubric: nil)
    assert_not report.feedback_visible?
  end

  test "student_feedback falls back to the AI rubric when no teacher_feedback is saved" do
    report = build_report(
      book_title: "AI폴백",
      rubric: { content: 5, emotion: 5, life: 5, structure: 5, spelling: 5,
                praise: [ "잘했어요" ], fix: [ "더 써 볼까요" ],
                grow: [ { text: "표현을 다양하게", standard_code: "2국05-01" } ] }
    )

    feedback = report.student_feedback
    assert_equal [ "잘했어요" ], feedback[:praise]
    assert_equal [ "더 써 볼까요" ], feedback[:fix]
    assert_equal [ { text: "표현을 다양하게", standard_code: "2국05-01" } ], feedback[:grow]
  end

  test "student_feedback prefers teacher_feedback over the AI rubric when present" do
    report = build_report(
      book_title: "교사우선",
      rubric: { praise: [ "AI 칭찬" ], fix: [ "AI 보완" ], grow: [ { text: "AI 제안", standard_code: "2국05-01" } ] },
      teacher_feedback: { praise: [ "교사 칭찬" ], fix: [ "교사 보완" ], grow: [ { text: "교사 제안", standard_code: "2국05-01" } ] }
    )

    feedback = report.student_feedback
    assert_equal [ "교사 칭찬" ], feedback[:praise]
    assert_equal [ "교사 보완" ], feedback[:fix]
    assert_equal "교사 제안", feedback[:grow].first[:text]
  end

  # teacher_feedback 은 grow 항목별 고정 입력(text만 편집)이라 standard_code 없이 저장될 수 있다.
  # student_feedback 은 이런 부분 데이터도 항상 {text:, standard_code:} 해시로 정규화해
  # 뷰의 해시 접근(grow[:text])이 문자열 크래시("..."[:text]) 없이 동작하게 한다.
  test "student_feedback normalizes teacher-edited grow entries into hashes even without a standard_code" do
    report = build_report(
      book_title: "정규화",
      rubric: {},
      teacher_feedback: { grow: [ { "text" => "문장만 있는 성장 제안" } ] }
    )

    assert_equal [ { text: "문장만 있는 성장 제안", standard_code: "" } ], report.student_feedback[:grow]
  end

  test "teacher_feedback round-trips through JSON and is readable via student_feedback after reload" do
    report = build_report(book_title: "라운드트립", rubric: {}).tap(&:save!)
    report.update!(teacher_feedback: { praise: [ "저장 확인" ], fix: [], grow: [ { text: "제안", standard_code: "2국05-01" } ] })

    feedback = Report.find(report.id).student_feedback
    assert_equal [ "저장 확인" ], feedback[:praise]
    assert_equal [], feedback[:fix]
    assert_equal [ { text: "제안", standard_code: "2국05-01" } ], feedback[:grow]
  end

  # 승인 시 상세 방송(broadcast_detail_refresh)이 실패해도 이미 커밋된 첨삭 결과를 뒤집지 않는다
  # (AiReviewJob·Teacher::ReviewsController 양쪽이 이 내부 rescue 계약에 의존한다).
  test "broadcast_detail_refresh swallows broadcast failures without raising or flipping ai_status" do
    report = build_report(book_title: "방송실패", ai_status: :done, rubric: { content: 5 }, reviewed: true).tap(&:save!)

    def report.broadcast_replace_to(*)
      raise "boom"
    end

    assert_nothing_raised { report.broadcast_detail_refresh }
    assert report.reload.done?
  end

  # --- OCR 사진 표시(display_photo / display_photo?) ---

  test "display_photo returns the report's own attached photo" do
    report = ocr_report_with_photo
    assert report.display_photo.attached?
    assert_equal report.photo.blob.id, report.display_photo.blob.id
  end

  test "display_photo climbs the revision chain to the root photo across generations" do
    root = ocr_report_with_photo
    first = revision_of(root)
    second = revision_of(first)

    assert_not second.photo.attached?
    assert_equal root.photo.blob.id, second.display_photo.blob.id
  end

  test "display_photo is nil when neither the report nor its ancestors have a photo" do
    report = revision_of(build_report(input_mode: :ocr, book_title: "사진없음").tap(&:save!))
    assert_nil report.display_photo
  end

  test "display_photo stops at the depth cap instead of walking an unbounded chain" do
    root = ocr_report_with_photo
    leaf = 12.times.inject(root) { |parent, _| revision_of(parent) }

    # 사진이 depth cap(10) 너머에 있으면 무한 순회 대신 nil 로 포기한다.
    assert_nil leaf.display_photo
  end

  test "display_photo memoizes so repeated renders do not re-query the revision chain" do
    revision = revision_of(ocr_report_with_photo)
    revision.display_photo # warm

    assert_equal 0, count_queries { 5.times { revision.display_photo } }
  end

  test "display_photo? requires both ocr input mode and a resolvable photo" do
    assert ocr_report_with_photo.display_photo?

    keyboard = build_report(input_mode: :keyboard, book_title: "키보드").tap(&:save!)
    attach_photo(keyboard)
    assert_not keyboard.display_photo?

    assert_not build_report(input_mode: :ocr, book_title: "무사진").tap(&:save!).display_photo?
  end

  private

  def build_report(attrs = {})
    Report.new({ user: @user, classroom: @classroom, book_title: "기본 제목" }.merge(attrs))
  end

  def ocr_report_with_photo
    build_report(input_mode: :ocr, book_title: "사진 독후감").tap do |report|
      report.save!
      attach_photo(report)
    end
  end

  def attach_photo(report)
    report.photo.attach(io: StringIO.new(png_bytes), filename: "handwriting.png", content_type: "image/png")
    report
  end

  # `ReportsController#revise` 와 동일하게 부모의 input_mode 만 승계하고 photo 는 복사하지 않는다.
  def revision_of(parent)
    Report.create!(user: parent.user, classroom: parent.classroom, book_title: parent.book_title,
                   input_mode: parent.input_mode, revision_of: parent)
  end

  def count_queries
    count = 0
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |_, _, _, _, payload|
      count += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name])
    end
    yield
    count
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  # 실제 매직바이트를 가진 최소 미디어 페이로드.
  def png_bytes
    [ 137, 80, 78, 71, 13, 10, 26, 10 ].pack("C*") + ("\x00" * 64)
  end

  def wav_bytes
    "RIFF" + [ 36 ].pack("V") + "WAVE" + "fmt " + ("\x00" * 32)
  end
end
