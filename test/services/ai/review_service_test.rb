require "test_helper"

class Ai::ReviewServiceTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "리뷰학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @user = User.create!(school: @school, classroom: @classroom, name: "리뷰학생", password: "password",
                         ai_consent: true, privacy_consent_at: Time.current)
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

  test "does not call Claude and falls back for a student without AI consent (P1-1)" do
    non_consenting = User.create!(school: @school, classroom: @classroom, name: "미동의리뷰학생", password: "password")
    report = Report.create!(user: non_consenting, classroom: @classroom, book_title: "책", body: "본문 내용입니다.")
    called = false
    client = StubClient.new(configured: true)
    client.define_singleton_method(:generate) { |**| called = true; {} }

    result = Ai::ReviewService.new(client: client).call(report)

    assert_not called, "미동의 학생은 configured 클라이언트라도 Claude 를 호출하지 않는다"
    assert_valid_review(result)
  end

  test "falls back to rule-based review on ApiError" do
    client = StubClient.new(configured: true, error: Ai::ClaudeClient::ApiError.new("boom"))
    result = Ai::ReviewService.new(client: client).call(@report)
    assert_valid_review(result)
  end

  test "falls back to rule-based review on NotConfigured raised mid-call" do
    client = StubClient.new(configured: true, error: Ai::ClaudeClient::NotConfigured.new("blank"))
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

  # 베타 리뷰: 제안이 한꺼번에 너무 많다. 모델이 프롬프트 상한을 넘겨도 학년군 상한까지만 남긴다
  # (프롬프트가 "중요한 것부터" 쓰게 하므로 앞에서부터 자른다).
  test "trims fix and grow to the band's feedback limits, keeping the first items" do
    response = {
      "level" => "B",
      "rubric" => { "content" => 3, "emotion" => 3, "life" => 3, "structure" => 3, "spelling" => 3 },
      "praise" => [ "칭찬1", "칭찬2" ],
      "fix" => [ "보완1", "보완2", "보완3" ],
      "grow" => [ { "text" => "성장1", "standard_code" => "[2국02-04]" },
                  { "text" => "성장2", "standard_code" => "[2국05-02]" } ],
      "pts" => 20
    }

    @classroom.update!(grade: 1)
    g12 = Ai::ReviewService.new(client: StubClient.new(configured: true, response: response)).call(@report)
    assert_equal [ "보완1" ], g12[:fix], "1~2학년군은 고칠 점 딱 한 가지"
    assert_equal [ "성장1" ], g12[:grow].map { |g| g[:text] }
    assert_equal [ "칭찬1", "칭찬2" ], g12[:praise], "칭찬은 자르지 않는다"

    @classroom.update!(grade: 5)
    g56 = Ai::ReviewService.new(client: StubClient.new(configured: true, response: response)).call(@report.reload)
    limits = ReadingDomain.feedback_limits(:g56)
    assert_equal [ "보완1", "보완2" ].first(limits[:fix]), g56[:fix]
    assert_equal limits[:grow], g56[:grow].size
  end

  # 무의미 입력 게이트가 지시하는 응답(칭찬·성장 제안 없음, 전 축 0점, 다시 써 달라는 부탁 하나)을
  # 스키마 이탈로 오판해 규칙기반 폴백(무조건 칭찬)으로 떨어뜨리지 않는다.
  test "accepts the non-attempt response shape without falling back" do
    response = {
      "level" => "C",
      "rubric" => { "content" => 0, "emotion" => 0, "life" => 0, "structure" => 0, "spelling" => 0 },
      "praise" => [],
      "fix" => [ "책에서 기억에 남는 장면과 그때 든 생각을 두세 문장으로 다시 써 줄래요?" ],
      "grow" => [],
      "pts" => 10
    }
    result = Ai::ReviewService.new(client: StubClient.new(configured: true, response: response)).call(@report)

    assert_equal "C", result[:level]
    assert_equal 10, result[:pts]
    assert_equal [], result[:praise]
    assert_equal [], result[:grow]
    assert_equal 1, result[:fix].size
    assert result[:rubric].values.all?(&:zero?)
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
