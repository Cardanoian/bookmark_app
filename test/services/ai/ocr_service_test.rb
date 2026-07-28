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
    assert_not client.generate_args.fetch(:generation_config, {}).key?(:temperature),
      "Claude 3.5에서 폐기된 temperature 설정을 OCR 요청에 보내면 안 된다"
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
end
