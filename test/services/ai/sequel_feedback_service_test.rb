require "test_helper"

# 뒷이야기 격려 코멘트 서비스(review_service 미러). 키 있으면 LLM, 무키/실패/스키마이탈이면 규칙기반 폴백.
# 정직한 AI: 평가 대상은 프롬프트에 든 "학생 글"(책 아님)이라 body 전문이 프롬프트에 들어간다.
class Ai::SequelFeedbackServiceTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "코멘트학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @author = User.create!(school: @school, classroom: @classroom, name: "코멘트학생", password: "password",
                           ai_consent: true, privacy_consent_at: Time.current)
    @book = Book.create!(title: "코멘트책", author: "지은이", category: :recommended)
    @sequel = BookSequel.create!(user: @author, book: @book, classroom: @classroom,
                                 body: "주인공은 마법의 문을 열고 새로운 세계로 떠났어요.")
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

  test "uses the LLM comment when the client is configured" do
    client = StubClient.new(configured: true, response: { "comment" => "상상력이 반짝이는 이야기예요!" })
    assert_equal "상상력이 반짝이는 이야기예요!",
                 Ai::SequelFeedbackService.new(client: client).call(@sequel)
  end

  test "falls back to a rule-based comment when unconfigured (no network)" do
    comment = Ai::SequelFeedbackService.new(client: StubClient.new(configured: false)).call(@sequel)
    assert comment.present?
  end

  test "falls back without calling Gemini for an author without AI consent (P1-1)" do
    non_consenting = User.create!(school: @school, classroom: @classroom, name: "미동의코멘트학생", password: "password")
    sequel = BookSequel.create!(user: non_consenting, book: @book, classroom: @classroom,
                                body: "새로운 세계로 떠나는 뒷이야기를 상상했어요.")
    called = false
    client = StubClient.new(configured: true)
    client.define_singleton_method(:generate) { |**| called = true; { "comment" => "x" } }

    comment = Ai::SequelFeedbackService.new(client: client).call(sequel)

    assert_not called, "미동의 학생 창작글은 Gemini 로 보내지 않는다"
    assert comment.present?
  end

  test "falls back on ApiError" do
    client = StubClient.new(configured: true, error: Ai::GeminiClient::ApiError.new("boom"))
    assert Ai::SequelFeedbackService.new(client: client).call(@sequel).present?
  end

  test "falls back when the comment is blank or the schema is invalid" do
    blank = StubClient.new(configured: true, response: { "comment" => "  " })
    assert Ai::SequelFeedbackService.new(client: blank).call(@sequel).present?

    bad = StubClient.new(configured: true, response: "not a hash")
    assert Ai::SequelFeedbackService.new(client: bad).call(@sequel).present?
  end

  # 정직한 AI: 프롬프트가 학생 글 전문(body)을 담아야 환각 없이 "학생 글"을 평가한다.
  class CapturingClient
    attr_reader :contents, :system_instruction

    def configured? = true

    def generate(contents:, system_instruction:, **)
      @contents = contents
      @system_instruction = system_instruction
      { "comment" => "좋아요" }
    end
  end

  test "sends the student's story body (not book facts) into the prompt" do
    client = CapturingClient.new
    Ai::SequelFeedbackService.new(client: client).call(@sequel)

    prompt_text = client.contents.first[:parts].first[:text]
    assert_includes prompt_text, @sequel.body
    assert_includes client.system_instruction, "격려"
  end
end
