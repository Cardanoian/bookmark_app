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

  test "marks the report failed (not stuck pending) when OcrService raises a Gemini API error" do
    stub_new(Ai::OcrService, RaisingStub.new(Ai::GeminiClient::ApiError.new("gemini boom"))) do
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
    assert_turbo_stream_broadcasts([ @user, :report_editor ], count: 2) do
      stub_new(Ai::OcrService, OcrStub.new("인식된 손글씨 본문")) do
        OcrJob.perform_now(@report)
      end
    end

    status_html = OcrJob.new.send(:ocr_ready_status_html)
    assert_includes status_html, 'id="ocr_reading_status"'
    assert_includes status_html, "제출하기"
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
