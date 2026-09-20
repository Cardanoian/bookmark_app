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

  # 없는 입력 방식 값은 예외(ArgumentError → 500)가 아니라 검증 오류가 된다. 폼으로는 생기지 않고
  # 조작한 요청(report[input_mode]=bogus)에서만 오는 값이다.
  test "an unknown input_mode is a validation error instead of an exception" do
    report = build_report
    assert_nothing_raised { report.input_mode = "bogus" }
    assert_not report.valid?
    assert report.errors.of_kind?(:input_mode, :inclusion)
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

  test "feedback_visible? requires a teacher approval of the completed review of the current version" do
    report = build_report(book_title: "게이트책")
    assert_not report.feedback_visible?, "미첨삭·미검토 상태는 노출 대상이 아니다"

    report.assign_attributes(review_ready_attributes)
    assert report.review_ready?
    assert_not report.feedback_visible?, "reviewed 가 아니면 첨삭이 완성돼도 숨겨야 한다"

    report.reviewed = true
    assert report.feedback_visible?, "현재 버전의 완성된 첨삭을 승인하면 노출한다"
  end

  # F3(BUG_FIX_PLAN §5.1): "지금 제출의 첨삭이 완성됐는가"는 done·루브릭만으로 판단하지 않는다.
  test "review_ready? needs a submitted report whose completed version equals the current version" do
    ready = review_ready_attributes
    assert build_report(ready).review_ready?

    {
      "초안(미제출)" => { submitted_at: nil },
      "대기" => { ai_status: :pending }, "처리 중" => { ai_status: :processing }, "실패" => { ai_status: :failed },
      "루브릭 없음" => { rubric: nil }, "빈 루브릭" => { rubric: {} },
      "버전 0" => { review_version: 0, completed_review_version: 0 },
      "완료 버전 없음" => { completed_review_version: nil },
      # 고쳐 다시 낸 글: 이전 제출의 done·루브릭이 남아 있어도 새 버전은 아직 확정되지 않았다.
      "다시 낸 글(이전 결과만 있음)" => { review_version: 2, completed_review_version: 1 }
    }.each do |label, override|
      report = build_report(ready.merge(override).merge(reviewed: true))
      assert_not report.review_ready?, "#{label}: 완성된 첨삭이 아니다"
      assert_not report.feedback_visible?, "#{label}: 승인 표시가 있어도 학생에게 보이지 않는다"
    end
  end

  test "record_submission! issues the next version and resets the review state" do
    report = build_report(book_title: "버전책", body: "본문")
    report.save!
    assert_equal [ 0, nil ], [ report.review_version, report.completed_review_version ], "초안은 버전 0"

    assert_equal 1, report.record_submission!
    first_submitted_at = report.reload.submitted_at
    assert report.pending?
    assert_not report.review_ready?

    report.update_columns(review_ready_attributes(submitted_at: first_submitted_at).merge(
      ai_status: Report.ai_statuses[:done], reviewed: true, reviewed_at: Time.current, shared: true,
      teacher_comment: "옛 코멘트", teacher_feedback: { "praise" => [ "옛 칭찬" ] }, teacher_rubric: { "content" => 5 }
    ))
    BoardPost.create!(report: report)
    assert report.reload.feedback_visible?

    travel 1.hour do
      assert_equal 2, report.record_submission!, "재제출마다 버전이 1 오른다"
    end

    report.reload
    assert_equal 1, report.completed_review_version, "완료 버전은 새 결과가 확정될 때까지 현재 버전과 어긋난다"
    assert_not report.review_ready?, "이전 제출의 루브릭이 남아 있어도 완성된 첨삭이 아니다"
    assert_not report.reviewed?, "이전 승인은 풀린다"
    assert_nil report.reviewed_at
    assert_equal [ nil, nil, nil ], [ report.teacher_comment, report.teacher_feedback, report.teacher_rubric ]
    assert_not report.shared?, "공유도 함께 걷는다"
    assert_nil report.board_post
    assert_equal first_submitted_at.to_i, report.submitted_at.to_i, "처음 낸 시각은 그대로다"
  end

  # 이 객체를 읽은 뒤에 다른 요청이 승인했어도(메모리의 reviewed 는 false) 새 제출은 미승인으로 기록된다.
  test "record_submission! resets an approval it has not seen in memory" do
    report = build_report(review_ready_attributes)
    report.save!
    stale = Report.find(report.id)
    assert_equal :approved, Report.find(report.id).approve!(seen_version: 1)

    stale.record_submission!

    assert_not report.reload.reviewed?
    assert_equal 2, report.review_version
  end

  test "approve! only approves the version the teacher has seen" do
    report = build_report(review_ready_attributes)
    report.save!

    assert_equal :stale, report.approve!(seen_version: nil), "버전을 싣지 않은 요청은 현재 버전으로 채워 승인하지 않는다"
    assert_equal :stale, report.approve!(seen_version: 2)
    assert_equal :stale, report.approve!(seen_version: "abc")
    assert_not report.reload.reviewed?

    assert_equal :approved, report.approve!(seen_version: "1")
    approved_at = report.reload.reviewed_at
    assert report.reviewed?

    travel 1.minute do
      assert_equal :already, report.approve!(seen_version: 1)
    end
    assert_equal approved_at, report.reload.reviewed_at, "재승인은 승인 시각을 덮어쓰지 않는다"

    report.record_submission!
    assert_equal :stale, report.approve!(seen_version: 1), "다시 낸 글은 옛 화면에서 승인되지 않는다"
    assert_equal :not_ready, report.approve!(seen_version: 2), "새 버전의 첨삭이 끝나기 전에는 승인되지 않는다"
    assert_not report.reload.reviewed?
  end

  test "review_retryable? is true for a failed or stalled current version only" do
    fresh = build_report(ai_status: :pending, submitted_at: Time.current, review_version: 1)
    fresh.save!
    assert_not fresh.review_retryable?, "방금 낸 글은 작업을 기다리는 중이다"

    fresh.update_columns(updated_at: (Report::REVIEW_STALLED_AFTER + 1.minute).ago)
    assert fresh.review_retryable?, "오래 멈춘 대기 글은 다시 요청할 수 있다"

    assert build_report(ai_status: :failed, submitted_at: Time.current, review_version: 1).review_retryable?
    assert_not build_report(review_ready_attributes).review_retryable?, "완성된 첨삭은 다시 요청하지 않는다"
    assert_not build_report(ai_status: :failed).review_retryable?, "미제출 초안(사진 판독 실패)은 대상이 아니다"
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

    # broadcast_detail_refresh 는 방송 직전에 DB 에서 다시 읽은 **다른 인스턴스**로 방송한다 — 이 객체의 싱글턴을
    # 스텁하면 걸리지 않아 테스트가 공허하게 통과한다. 클래스 단위로 덮었다가 지운다(Turbo 모듈의 원래 메서드로 복귀).
    raised = false
    Report.define_method(:broadcast_replace_to) do |*, **|
      raised = true
      raise "boom"
    end
    begin
      assert_nothing_raised { report.broadcast_detail_refresh }
    ensure
      Report.send(:remove_method, :broadcast_replace_to)
    end

    assert raised, "방송이 실제로 시도됐고 그 예외를 삼켰다"
    assert report.reload.done?
  end

  # `scope :review_ready`(SQL)와 `review_ready?`(Ruby)는 같은 판정이다 — 한쪽만 고치면 글 화면과 성장 화면·인쇄 문서가 어긋난다.
  test "the review_ready scope and predicate agree across the state matrix" do
    ready = review_ready_attributes
    [
      {}, { reviewed: true }, { submitted_at: nil }, { ai_status: :pending }, { ai_status: :processing },
      { ai_status: :failed }, { rubric: nil }, { rubric: {} }, { review_version: 0, completed_review_version: 0 },
      { completed_review_version: nil }, { review_version: 2, completed_review_version: 1 },
      { review_version: 3, completed_review_version: 3 }
    ].each { |override| build_report(ready.merge(override)).save! }

    by_predicate = Report.order(:id).select(&:review_ready?).map(&:id)
    assert_equal by_predicate, Report.review_ready.order(:id).pluck(:id)
    assert_equal 3, by_predicate.size
    assert_equal Report.order(:id).select(&:feedback_visible?).map(&:id), Report.approved.order(:id).pluck(:id)
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

  # 자동 저장 대상·첫 제출 판정(2026-09-13 리뷰 후속). 원본을 지운 고쳐쓰기 초안은 revision_of_id 가
  # nil 이지만 원본의 rubric 을 물려받는다 — "첨삭 받은 적 없는 사진 초안"과 가르는 기준이 rubric 이다.
  test "autosave_eligible? excludes only the first-submit screen of a photo draft" do
    rubric = { content: 3, emotion: 3, life: 2, structure: 3, spelling: 4 }
    parent = build_report(submitted_at: 1.day.ago, rubric: rubric).tap(&:save!)

    assert build_report.autosave_eligible?, "키보드 초안"
    assert_not build_report(input_mode: :ocr).autosave_eligible?, "사진 초안의 첫 제출 화면"
    assert build_report(input_mode: :ocr, revision_of: parent, rubric: rubric).autosave_eligible?, "사진 원본의 고쳐쓰기"
    assert build_report(input_mode: :ocr, rubric: rubric).autosave_eligible?, "원본을 지운 사진 고쳐쓰기"
    assert_not build_report(submitted_at: Time.current).autosave_eligible?, "이미 낸 글"
  end

  test "first_submission? covers never-reviewed reports and orphaned revision drafts" do
    rubric = { content: 3, emotion: 3, life: 2, structure: 3, spelling: 4 }
    parent = build_report(submitted_at: 1.day.ago, rubric: rubric).tap(&:save!)

    assert build_report.first_submission?, "첨삭 받은 적 없는 초안"
    assert build_report(rubric: rubric).first_submission?, "원본을 지운 고쳐쓰기 초안"
    assert_not build_report(revision_of: parent, rubric: rubric).first_submission?, "원본이 있는 고쳐쓰기 초안"
    assert_not build_report(rubric: rubric, submitted_at: Time.current).first_submission?, "이미 첨삭 받은 글"
  end

  test "draft_version changes on every save with microsecond precision" do
    report = build_report.tap(&:save!)
    first = report.draft_version
    assert_match(/\.\d{6}Z\z/, first)

    report.update!(body: "더 쓴 글")
    assert_not_equal first, report.draft_version
    assert_equal report.draft_version, Report.find(report.id).draft_version, "저장 직후 값과 다시 읽은 값이 같다"
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
