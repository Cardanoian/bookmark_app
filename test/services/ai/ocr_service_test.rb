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
    service = Ai::OcrService.new(client: client)

    assert_equal "인식된 손글씨 본문", service.call(@report.photo.blob)
  end

  # OCR 만 Haiku 가 아니라 Sonnet 5 를 쓴다(Haiku 는 손글씨 한글 CER 51%). effort 를 low 로 묶지 않으면
  # 흐린 사진에서 생각이 길어져 비용이 불고 30s 타임아웃을 넘는다 — docs/AI_MODEL_SELECTION.md §9.
  test "requests the OCR model at low effort without sampling params" do
    client = StubClient.new(configured: true, response: { "text" => "본문" })
    Ai::OcrService.new(client: client).call(@report.photo.blob)

    config = client.generate_args.fetch(:generation_config)
    assert_equal "claude-sonnet-5", config[:model]
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
    service = Ai::OcrService.new(client: client)
    service.define_singleton_method(:resized_jpeg) { |_file| "resized-jpeg-bytes" }

    service.call(@report.photo.blob)

    image = image_part(client)
    assert_equal "image/jpeg", image[:mimeType]
    assert_equal Base64.strict_encode64("resized-jpeg-bytes"), image[:data]
  end

  # libvips 가 없는 호스트에서는 LoadError(StandardError 가 아니다)가 난다. 그래도 판독은 원본으로 이어간다.
  test "falls back to the original image when resizing fails, including LoadError" do
    [ LoadError.new("libvips missing"), RuntimeError.new("corrupt image") ].each do |error|
      client = StubClient.new(configured: true, response: { "text" => "본문" })
      service = Ai::OcrService.new(client: client)
      service.define_singleton_method(:resized_jpeg) { |_file| raise error }

      assert_equal "본문", service.call(@report.photo.blob)

      image = image_part(client)
      assert_equal "image/png", image[:mimeType]
      assert_equal Base64.strict_encode64("fake-image-bytes"), image[:data]
    end
  end

  test "handles a String response from the client without crashing" do
    client = StubClient.new(configured: true, response: "인식된 손글씨 본문")
    service = Ai::OcrService.new(client: client)

    assert_equal "인식된 손글씨 본문", service.call(@report.photo.blob)
  end

  test "handles an Array response from the client without crashing" do
    response = [ "인식된", "손글씨" ]
    client = StubClient.new(configured: true, response: response)
    service = Ai::OcrService.new(client: client)

    assert_equal response.to_s, service.call(@report.photo.blob)
  end

  test "raises ClaudeClient::ApiError instead of saving a blank OCR body" do
    client = StubClient.new(configured: true, response: { "text" => "" })
    service = Ai::OcrService.new(client: client)

    assert_raises(Ai::ClaudeClient::ApiError) do
      service.call(@report.photo.blob)
    end
  end

  private

  def image_part(client)
    client.generate_args.fetch(:contents).first[:parts].find { |part| part[:inlineData] }[:inlineData]
  end
end
