require "test_helper"

# Claude 줄거리 생성(게임 재구성 Phase 4 §1b). 무키·모름·저확신·스키마이탈이면 nil(저장 안 함),
# known+고확신일 때만 줄거리 문자열. 정직화: 기존 summary 를 프롬프트에 넣지 않는 독립 인식 테스트.
class Ai::BookSummaryServiceTest < ActiveSupport::TestCase
  setup do
    @book = Book.create!(title: "마당을 나온 암탉", author: "황선미",
                         publisher: "사계절", summary: "이미 있는 줄거리(넣지 말아야 함).", category: :recommended)
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

  test "returns nil without an API key (no network)" do
    assert_nil Ai::BookSummaryService.new(client: StubClient.new(configured: false)).call(@book)
  end

  test "returns the summary when the book is known with high confidence" do
    client = StubClient.new(configured: true,
      response: { "known" => true, "confidence" => 0.9, "summary" => "잎싹이 마당을 나와 자유를 찾는 이야기예요." })
    assert_equal "잎싹이 마당을 나와 자유를 찾는 이야기예요.",
                 Ai::BookSummaryService.new(client: client).call(@book)
  end

  test "returns nil when the model says it does not know the book" do
    client = StubClient.new(configured: true,
      response: { "known" => false, "confidence" => 0.9, "summary" => "" })
    assert_nil Ai::BookSummaryService.new(client: client).call(@book)
  end

  test "returns nil when confidence is below the threshold (hallucination guard)" do
    client = StubClient.new(configured: true,
      response: { "known" => true, "confidence" => 0.5, "summary" => "확신 낮은 줄거리." })
    assert_nil Ai::BookSummaryService.new(client: client).call(@book)
  end

  test "returns nil when known+confident but the summary is blank" do
    client = StubClient.new(configured: true,
      response: { "known" => true, "confidence" => 0.95, "summary" => "   " })
    assert_nil Ai::BookSummaryService.new(client: client).call(@book)
  end

  test "returns nil on ApiError (fallback, no crash)" do
    client = StubClient.new(configured: true, error: Ai::ClaudeClient::ApiError.new("boom"))
    assert_nil Ai::BookSummaryService.new(client: client).call(@book)
  end

  test "returns nil when the response is not a hash (schema violation)" do
    client = StubClient.new(configured: true, response: "not a hash")
    assert_nil Ai::BookSummaryService.new(client: client).call(@book)
  end

  # 정직화(§3.1·P2-6): 독립 인식 테스트라야 진짜 아는 책인지 판별된다 → 기존 summary 는 프롬프트에
  # 넣지 않고, 서지 정보(제목·지은이·출판사)만 넣는다.
  class CapturingClient
    attr_reader :contents, :system_instruction

    def configured? = true

    def generate(contents:, system_instruction:, **)
      @contents = contents
      @system_instruction = system_instruction
      { "known" => true, "confidence" => 0.9, "summary" => "좋아요" }
    end
  end

  test "sends bibliographic info but NOT the existing summary into the prompt" do
    client = CapturingClient.new
    Ai::BookSummaryService.new(client: client).call(@book)

    prompt_text = client.contents.first[:parts].first[:text]
    assert_includes prompt_text, @book.title
    assert_includes prompt_text, @book.author
    assert_not_includes prompt_text, @book.summary, "기존 summary 는 프롬프트에 넣지 않는다(자기참조 최소화)"
  end
end
