require "test_helper"

class Ai::OcrServiceTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "OCR학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @user = User.create!(school: @school, classroom: @classroom, name: "OCR학생", password: "password")
    @report = Report.create!(user: @user, classroom: @classroom, book_title: "책")
    @report.photo.attach(io: StringIO.new("fake-image-bytes"), filename: "hw.png", content_type: "image/png")
  end

  class StubClient
    attr_reader :generate_args

    def initialize(configured:, response: nil)
      @configured = configured
      @response = response
    end

    def configured? = @configured

    def generate(**args)
      @generate_args = args
      @response
    end
  end

  test "raises Unavailable when the client is unconfigured" do
    service = Ai::OcrService.new(client: StubClient.new(configured: false))
    assert_raises(Ai::OcrService::Unavailable) do
      service.call(@report.photo.blob)
    end
  end

  test "returns recognized text when the client is configured" do
    client = StubClient.new(configured: true, response: { "text" => "인식된 손글씨 본문" })
    service = service_with_resize(client)

    assert_equal "인식된 손글씨 본문", service.call(@report.photo.blob)
  end

  # OCR 만 Haiku 가 아니라 Sonnet 5.5 를 쓴다(Haiku 는 손글씨 한글 CER 51%). effort 를 low 로 묶지 않으면
  # 흐린 사진에서 생각이 길어져 비용이 불고 30s 타임아웃을 넘는다 — docs/AI_MODEL_SELECTION.md §9.
  test "requests the OCR model at low effort without sampling params" do
    client = StubClient.new(configured: true, response: { "text" => "본문" })
    service_with_resize(client).call(@report.photo.blob)

    config = client.generate_args.fetch(:generation_config)
    assert_equal "claude-sonnet-5-5", config[:model]
    assert_equal({ effort: "low" }, config[:output_config])
    assert_not config.key?(:temperature), "Sonnet 5 는 temperature 를 보내면 400 이다"
  end

  # 30s 로 끊기면 재시도가 이미 과금된 요청을 되풀이한다 — OCR 만 읽기 제한을 늘린다.
  test "default client uses the longer OCR read timeout" do
    client = Ai::OcrService.new.instance_variable_get(:@client)
    assert_equal Ai::OcrService::READ_TIMEOUT, client.send(:connection).options.timeout
    assert_equal 30, Ai::ClaudeClient.new.send(:connection).options.timeout
  end

  test "sends a resized JPEG when the image can be processed" do
    client = StubClient.new(configured: true, response: { "text" => "본문" })

    service_with_resize(client).call(@report.photo.blob)

    image = image_part(client)
    assert_equal "image/jpeg", image[:mimeType]
    assert_equal Base64.strict_encode64("resized-jpeg-bytes"), image[:data]
  end

  # 다시 쓰지 못한 사진은 원본(촬영 위치 등 메타데이터가 남은 것)을 보내지 않는다 — 처리방침 제7조 ②·부록 1
  # 이 "사진 파일 정보를 지운 뒤 보낸다"고 약속한다(2026-11-09, 예전에는 원본으로 이어 갔다).
  # libvips 가 없는 호스트에서는 LoadError(StandardError 가 아니다)가 나므로 그것도 막아야 한다.
  test "refuses to send the original image when re-encoding fails, including LoadError" do
    [ LoadError.new("libvips missing"), RuntimeError.new("corrupt image") ].each do |error|
      client = StubClient.new(configured: true, response: { "text" => "본문" })
      service = Ai::OcrService.new(client: client)
      service.define_singleton_method(:resized_jpeg) { |_file| raise error }

      raised = assert_raises(Ai::OcrService::ImageNotPrepared) { service.call(@report.photo.blob) }

      assert_nil client.generate_args, "#{error.class}: 사진을 보내는 요청이 나가면 안 된다"
      assert_includes raised.message, error.class.name
    end
  end

  # ── 실제 libvips 경로 ─────────────────────────────────────────────────────────
  # 위 테스트들은 다시 쓰기를 대역으로 둔다. 아래 둘은 진짜 libvips 로 촬영 정보(EXIF)가 실제로 빠지는지,
  # 빠지지 않은 결과를 막는지 본다. libvips 가 없는 개발기에서는 건너뛰고 CI(libvips 설치)·운영 이미지에서 돈다.

  test "re-encoding on real libvips drops EXIF from the photo" do
    require_libvips!
    file = Tempfile.new([ "exif", ".jpg" ], binmode: true)
    file.write(jpeg_with_exif)
    file.flush

    bytes = Ai::OcrService.new(client: StubClient.new(configured: true)).send(:resized_jpeg, File.open(file.path))

    assert_nil bytes.index("Exif\x00\x00".b), "다시 쓴 사진에 EXIF 가 남아 있으면 안 된다"
    assert_empty Vips::Image.new_from_buffer(bytes, "").get_fields.grep(/\A(exif|xmp|iptc)-/)
  ensure
    file&.close!
  end

  # image_processing 은 saver 가 모르는 옵션을 예외 없이 버린다 — `strip` 이 조용히 무시돼 다시 쓴 결과에 EXIF 가
  # 남아도 보내지 않아야 한다. 인코딩(encode_jpeg)만 대역으로 바꿔 사후 검사가 실제 전송 경로에 걸려 있는지 본다.
  test "a re-encode that still carries EXIF is not sent" do
    require_libvips!
    client = StubClient.new(configured: true, response: { "text" => "본문" })
    service = Ai::OcrService.new(client: client)
    leaked = jpeg_with_exif
    service.define_singleton_method(:encode_jpeg) { |_file| leaked }

    error = assert_raises(Ai::OcrService::ImageNotPrepared) { service.call(@report.photo.blob) }

    assert_includes error.message, "exif-data"
    assert_nil client.generate_args, "EXIF 가 남은 사진을 보내는 요청이 나가면 안 된다"
  end

  test "handles a String response from the client without crashing" do
    client = StubClient.new(configured: true, response: "인식된 손글씨 본문")
    service = service_with_resize(client)

    assert_equal "인식된 손글씨 본문", service.call(@report.photo.blob)
  end

  test "handles an Array response from the client without crashing" do
    response = [ "인식된", "손글씨" ]
    client = StubClient.new(configured: true, response: response)
    service = service_with_resize(client)

    assert_equal response.to_s, service.call(@report.photo.blob)
  end

  test "raises ClaudeClient::ApiError instead of saving a blank OCR body" do
    client = StubClient.new(configured: true, response: { "text" => "" })
    service = service_with_resize(client)

    assert_raises(Ai::ClaudeClient::ApiError) do
      service.call(@report.photo.blob)
    end
  end

  private

  # 테스트 사진은 진짜 이미지가 아니라 다시 쓰기가 실패한다(그러면 보내지 않는다) — 다시 쓰기는 대역으로 둔다.
  def service_with_resize(client)
    Ai::OcrService.new(client: client).tap do |service|
      service.define_singleton_method(:resized_jpeg) { |_file| "resized-jpeg-bytes" }
    end
  end

  def image_part(client)
    client.generate_args.fetch(:contents).first[:parts].find { |part| part[:inlineData] }[:inlineData]
  end
end
