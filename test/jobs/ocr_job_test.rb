require "test_helper"

class OcrJobTest < ActiveJob::TestCase
  setup do
    @school = School.create!(name: "OCR잡학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @user = User.create!(school: @school, classroom: @classroom, name: "OCR잡학생", password: "password",
                         ai_consent: true, privacy_consent_at: Time.current)
    @report = Report.create!(user: @user, classroom: @classroom, book_title: "책", input_mode: :ocr)
    @report.photo.attach(io: StringIO.new("fake-image-bytes"), filename: "hw.png", content_type: "image/png")
    # 동의 게이트가 무키(테스트 기본)로 막지 않도록 configured 스텁을 주입 — 기존 OCR 동작 검증용.
    OcrJob.gate_client_factory = -> { GateStub.new(true) }
  end

  teardown { OcrJob.reset_factories! }

  class GateStub
    def initialize(configured) = (@configured = configured)
    def configured? = @configured
  end

  class OcrStub
    def initialize(text)
      @text = text
    end

    def call(_blob)
      @text
    end
  end

  # 판독이 도는 **동안** 아이가 같은 글을 고쳐 쓰는 상황을 흉내 낸다(느린 API 구간의 경쟁).
  class MutatingStub
    def initialize(text, report, changes)
      @text = text
      @report = report
      @changes = changes
    end

    def call(_blob)
      Report.find(@report.id).update!(@changes)
      @text
    end
  end

  class RaisingStub
    def initialize(error)
      @error = error
    end

    def call(_blob)
      raise @error
    end
  end

  test "marks the report failed when OCR is unavailable (blank key, no network)" do
    OcrJob.perform_now(@report)
    assert @report.reload.failed?
  end

  test "marks the report failed (not stuck pending) when OcrService raises a Claude API error" do
    stub_new(Ai::OcrService, RaisingStub.new(Ai::ClaudeClient::ApiError.new("claude boom"))) do
      OcrJob.perform_now(@report)
    end

    assert @report.reload.failed?
  end

  test "sets the body and marks done when OCR succeeds (stubbed)" do
    stub_new(Ai::OcrService, OcrStub.new("인식된 손글씨 본문")) do
      OcrJob.perform_now(@report)
    end

    @report.reload
    assert_equal "인식된 손글씨 본문", @report.body
    assert @report.done?
  end

  # 판독 성공 방송은 본문 textarea 와 **상태 영역** 둘 다 교체해야 한다. 본문만 바꾸면 화면에
  # "사진에서 글자를 읽고 있어요" 배너가 그대로 남아, 글자가 채워졌는데도 아직 처리 중이라고
  # 말한다 — 학생이 제출하기를 누를 이유를 못 느끼고 떠나면 초안인 채로 남아 첨삭이 영영 안 붙는다.
  test "broadcasts both the body and the submit prompt when OCR succeeds" do
    assert_turbo_stream_broadcasts([ @report, :report_editor ], count: 2) do
      stub_new(Ai::OcrService, OcrStub.new("인식된 손글씨 본문")) do
        OcrJob.perform_now(@report)
      end
    end

    status_html = OcrJob.new.send(:ocr_ready_status_html)
    assert_includes status_html, 'id="ocr_reading_status"'
    assert_includes status_html, "제출하기"
  end

  # 사용자 단위 채널이던 시절, 같은 학생이 다른 탭에 열어 둔 **다른 초안**의 본문까지 이 판독 결과로
  # 바뀌었고 자동 저장이 그 엉뚱한 본문을 그 초안에 저장했다(2026-09-13 리뷰 #9). 방송은 이 글의 채널로만 간다.
  test "broadcasts only to this report's editor, not to the student's other drafts" do
    other_draft = Report.create!(user: @user, classroom: @classroom, book_title: "다른 책",
                                 body: "다른 탭에서 쓰는 글", input_mode: :keyboard)

    assert_no_turbo_stream_broadcasts([ other_draft, :report_editor ]) do
      assert_no_turbo_stream_broadcasts([ @user, :report_editor ]) do
        stub_new(Ai::OcrService, OcrStub.new("인식된 손글씨 본문")) do
          OcrJob.perform_now(@report)
        end
      end
    end
    assert_equal "다른 탭에서 쓰는 글", other_draft.reload.body
  end

  test "the failure notice also goes only to this report's editor" do
    assert_turbo_stream_broadcasts([ @report, :report_editor ], count: 1) do
      OcrJob.perform_now(@report)
    end
    assert @report.reload.failed?
  end

  test "does not run OCR (no Claude call) for a student without AI consent (P1-1)" do
    student = User.create!(school: @school, classroom: @classroom, name: "미동의OCR학생", password: "password")
    report = Report.create!(user: student, classroom: @classroom, book_title: "책", input_mode: :ocr)
    report.photo.attach(io: StringIO.new("fake"), filename: "hw.png", content_type: "image/png")

    # OcrService 가 호출되면 rescue 안 되는 RuntimeError 로 즉시 실패시켜 "호출되면 테스트 에러"로 감시한다.
    stub_new(Ai::OcrService, RaisingStub.new(RuntimeError.new("OCR must not run for a non-consenting student"))) do
      OcrJob.perform_now(report)
    end

    assert report.reload.failed?, "미동의 학생 사진은 OCR 없이 실패 처리된다"
  end

  # --- 늦게 끝난 판독 폐기(2026-09-16) ---
  # 판독은 몇 초에서 몇십 초가 걸린다. 그동안 아이는 같은 글을 직접 고쳐 쓰고 제출까지 할 수 있는데,
  # 예전에는 늦게 끝난 판독이 그 글을 조건 없이 덮어 아이가 낸 글이 사진 원문으로 되돌아갔다.

  test "판독하는 동안 글이 제출되면 본문도 상태도 건드리지 않는다" do
    digest = OcrJob.body_digest(@report)
    stub = MutatingStub.new("판독 원문", @report, submitted_at: Time.current, body: "아이가 낸 글", ai_status: :processing)

    stub_new(Ai::OcrService, stub) do
      OcrJob.perform_now(@report, body_digest: digest)
    end

    @report.reload
    assert_equal "아이가 낸 글", @report.body
    assert @report.processing?, "첨삭 상태(ai_status)를 판독이 덮어쓰지 않는다"
  end

  test "이미 낸 글이면 판독을 시작하지도 않는다" do
    @report.update!(submitted_at: Time.current, body: "아이가 낸 글", ai_status: :processing)

    # 호출되면 rescue 되지 않는 RuntimeError 로 즉시 드러낸다.
    stub_new(Ai::OcrService, RaisingStub.new(RuntimeError.new("OCR must not run for a submitted report"))) do
      OcrJob.perform_now(@report, body_digest: OcrJob.body_digest(@report))
    end

    @report.reload
    assert_equal "아이가 낸 글", @report.body
    assert @report.processing?
  end

  test "판독하는 동안 직접 쓴 글이 있으면 그 글을 두고 '그대로 두었어요'를 알린다" do
    digest = OcrJob.body_digest(@report)
    stub = MutatingStub.new("판독 원문", @report, body: "직접 쓴 글")

    assert_turbo_stream_broadcasts([ @report, :report_editor ], count: 1) do
      stub_new(Ai::OcrService, stub) do
        OcrJob.perform_now(@report, body_digest: digest)
      end
    end

    @report.reload
    assert_equal "직접 쓴 글", @report.body
    assert @report.done?, "화면이 '읽는 중'에 묶이지 않게 상태는 닫는다"
    assert_includes OcrJob.new.send(:ocr_kept_status_html), "그대로 두었어요"
  end

  test "지문 없이 온 옛 잡은 예전처럼 본문을 채운다" do
    stub_new(Ai::OcrService, OcrStub.new("인식된 손글씨 본문")) do
      OcrJob.perform_now(@report)
    end

    assert_equal "인식된 손글씨 본문", @report.reload.body
  end

  test "업로드한 사진에 이미 쓰던 글이 있으면 지문이 같아 정상 판독된다" do
    @report.update!(body: "사진을 붙이기 전에 쓰던 글")
    digest = OcrJob.body_digest(@report)

    stub_new(Ai::OcrService, OcrStub.new("판독 원문")) do
      OcrJob.perform_now(@report, body_digest: digest)
    end

    assert_equal "판독 원문", @report.reload.body
  end

  private

  # Minitest 6 dropped minitest/mock; temporarily swap `.new` on a service class
  # to return an injected double, then restore the inherited Class#new.
  def stub_new(klass, replacement)
    klass.define_singleton_method(:new) { |*, **| replacement }
    yield
  ensure
    klass.singleton_class.send(:remove_method, :new)
  end
end
