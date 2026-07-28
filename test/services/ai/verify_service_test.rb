require "test_helper"

class Ai::VerifyServiceTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "검증학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @user = User.create!(school: @school, classroom: @classroom, name: "검증학생", password: "password",
                         ai_consent: true, privacy_consent_at: Time.current)
  end

  class StubClient
    def initialize(configured:, response: nil, error: nil)
      @configured = configured
      @response = response
      @error = error
    end

    def configured? = @configured

    def generate(**)
      raise @error if @error

      @response
    end
  end

  test "returns a neutral result when unconfigured" do
    result = Ai::VerifyService.new(client: StubClient.new(configured: false)).call(create_report(body: "본문"))
    assert_nil result[:suspicion]
    assert_equal [], result[:reasons]
  end

  test "returns neutral without calling Claude for a student without AI consent (P1-1)" do
    non_consenting = User.create!(school: @school, classroom: @classroom, name: "미동의검증학생", password: "password")
    report = Report.create!(user: non_consenting, classroom: @classroom, book_title: "책", body: "본문")
    called = false
    client = StubClient.new(configured: true)
    client.define_singleton_method(:generate) { |**| called = true; { "suspicion" => 0.9, "reasons" => [] } }

    result = Ai::VerifyService.new(client: client).call(report)

    assert_not called, "미동의 학생 본문은 Claude 로 보내지 않는다"
    assert_nil result[:suspicion]
  end

  test "returns the model suspicion and reasons when configured" do
    client = StubClient.new(configured: true, response: { "suspicion" => 0.7, "reasons" => [ "표절 의심" ] })
    result = Ai::VerifyService.new(client: client).call(create_report(body: "본문"))

    assert_equal 0.7, result[:suspicion]
    assert_equal [ "표절 의심" ], result[:reasons]
  end

  test "returns a neutral result on ApiError" do
    client = StubClient.new(configured: true, error: Ai::ClaudeClient::ApiError.new("boom"))
    result = Ai::VerifyService.new(client: client).call(create_report(body: "본문"))

    assert_nil result[:suspicion]
    assert_equal [], result[:reasons]
  end

  test "logs a warning on ApiError so ops can see why authenticity came back neutral (no PII)" do
    client = StubClient.new(configured: true, error: Ai::ClaudeClient::ApiError.new("claude responded with status 500"))
    report = create_report(body: "민감한 학생 본문 내용")

    logged = capture_log_output { Ai::VerifyService.new(client: client).call(report) }

    assert_match(/VerifyService API failure/, logged)
    assert_match(/ApiError/, logged)
    assert_no_match(/민감한 학생 본문 내용/, logged, "report.body(개인정보) 는 로그에 남으면 안 된다")
  end

  test "max_similarity is zero when the classroom has no other reports" do
    report = create_report(body: "혼자 있는 글입니다.")
    assert_equal 0.0, Ai::VerifyService.max_similarity(report)
  end

  test "max_similarity is zero when there is no token overlap" do
    report = create_report(body: "사과 바나나 포도")
    create_report(body: "자동차 기차 비행기")
    assert_equal 0.0, Ai::VerifyService.max_similarity(report)
  end

  test "max_similarity detects overlap within the classroom and stays in 0..1" do
    report = create_report(body: "강아지 고양이 토끼 거북이")
    create_report(body: "강아지 고양이 토끼 다람쥐")

    similarity = Ai::VerifyService.max_similarity(report)
    assert_operator similarity, :>, 0.0
    assert_operator similarity, :<=, 1.0
  end

  private

  def create_report(body:)
    Report.create!(user: @user, classroom: @classroom, book_title: "책", body: body)
  end

  # Rails.logger 출력을 캡처해 검사한다(테스트가 끝나면 원래 로거로 복원).
  def capture_log_output
    previous_logger = Rails.logger
    io = StringIO.new
    Rails.logger = Logger.new(io)
    yield
    io.string
  ensure
    Rails.logger = previous_logger
  end
end
