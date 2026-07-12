require "test_helper"

class Ai::ReviewServiceTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "리뷰학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @user = User.create!(school: @school, classroom: @classroom, name: "리뷰학생", password: "password")
    @report = Report.create!(user: @user, classroom: @classroom, book_title: "책", body: "본문 내용입니다.")
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

  test "uses the LLM response when the client is configured" do
    response = {
      "level" => "A",
      "rubric" => { "content" => 5, "emotion" => 5, "life" => 5, "structure" => 4, "spelling" => 4 },
      "praise" => [ "좋아요" ],
      "fix" => [],
      "grow" => [ { "text" => "성장 제안", "standard_code" => "[6국05-06]" } ],
      "pts" => 30
    }
    result = Ai::ReviewService.new(client: StubClient.new(configured: true, response: response)).call(@report)

    assert_equal "A", result[:level]
    assert_equal 30, result[:pts]
    assert_equal 5, result[:rubric][:content]
    assert_equal [ { text: "성장 제안", standard_code: "[6국05-06]" } ], result[:grow]
  end

  test "falls back to rule-based review when unconfigured" do
    result = Ai::ReviewService.new(client: StubClient.new(configured: false)).call(@report)
    assert_valid_review(result)
  end

  test "falls back to rule-based review on ApiError" do
    client = StubClient.new(configured: true, error: Ai::GeminiClient::ApiError.new("boom"))
    result = Ai::ReviewService.new(client: client).call(@report)
    assert_valid_review(result)
  end

  test "falls back to rule-based review on NotConfigured raised mid-call" do
    client = StubClient.new(configured: true, error: Ai::GeminiClient::NotConfigured.new("blank"))
    result = Ai::ReviewService.new(client: client).call(@report)
    assert_valid_review(result)
  end

  test "falls back to rule-based review when the schema is invalid" do
    client = StubClient.new(configured: true, response: { "level" => "Z", "rubric" => {} })
    result = Ai::ReviewService.new(client: client).call(@report)
    assert_valid_review(result)
  end

  # system_instruction 을 포착해 학년군 프롬프트 선택을 검증하는 스텁.
  class CapturingClient
    attr_reader :system_instruction

    def configured? = true

    def generate(system_instruction:, **)
      @system_instruction = system_instruction
      { "level" => "B", "rubric" => { "content" => 3, "emotion" => 3, "life" => 3, "structure" => 3, "spelling" => 3 },
        "praise" => [], "fix" => [], "grow" => [], "pts" => 20 }
    end
  end

  test "selects the rubric prompt for the student's 학년군 band" do
    @classroom.update!(grade: 3)
    client = CapturingClient.new
    Ai::ReviewService.new(client: client).call(@report)

    assert_equal ReadingDomain.rubric_prompt(:g34), client.system_instruction
    assert_includes client.system_instruction, "초등학교 3~4학년"
  end

  test "fallback grow codes match the student's 학년군 band" do
    @classroom.update!(grade: 2)
    result = Ai::ReviewService.new(client: StubClient.new(configured: false)).call(@report)

    codes = ReadingDomain.achievement_standards(:g12).values
    result[:grow].each { |entry| assert_includes codes, entry[:standard_code] }
  end

  private

  def assert_valid_review(result)
    assert_includes %w[A B C], result[:level]
    assert_equal ReadingDomain::RUBRIC_AXES.sort, result[:rubric].keys.sort
    result[:rubric].each_value { |score| assert_includes 0..5, score }
    assert_includes ReadingDomain::LEVEL_POINTS.values, result[:pts]
    assert_kind_of Array, result[:grow]
  end
end
