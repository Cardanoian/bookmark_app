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

  # 학년군 제한을 프롬프트 지시에만 맡기지 않는다 — 모델이 학년군 밖 성취기준 코드를 줘도 서버가
  # 저장하지 않는다(Ai::ReviewService#normalize_grow). 제안 문장은 학생에게 줄 조언이라 남긴다.
  test "drops grow standard codes outside the student's 학년군 but keeps the suggestion text" do
    @classroom.update!(grade: 6)

    assert_equal({ text: "다른 학년군 제안", standard_code: "" }, grow_for("[4국05-01]", text: "다른 학년군 제안"),
                 "6학년(g56)에게 3~4학년군 코드는 저장하지 않는다")
    assert_equal "", grow_for("[2국05-02]")[:standard_code], "1~2학년군 코드도 저장하지 않는다"
    assert_equal "", grow_for("[6국05-99]")[:standard_code], "목록에 없는 지어낸 코드는 저장하지 않는다"
    assert_equal "", grow_for("[6국01-01]")[:standard_code], "같은 학년군이어도 목록 밖 영역(듣기·말하기)은 저장하지 않는다"
    assert_equal "", grow_for("")[:standard_code]
    assert_equal "", grow_for(nil)[:standard_code]
  end

  test "keeps allowed grow standard codes and normalizes bracket or spacing variants" do
    @classroom.update!(grade: 6)

    assert_equal({ text: "성장 제안", standard_code: "[6국05-06]" }, grow_for("[6국05-06]"))
    assert_equal "[6국05-06]", grow_for("6국05-06")[:standard_code], "대괄호 없는 표기도 목록 표기로 저장한다"
    assert_equal "[6국05-06]", grow_for(" [ 6국 05-06 ] ")[:standard_code], "공백이 섞인 표기도 목록 표기로 저장한다"

    @classroom.update!(grade: 3)
    assert_equal "[4국05-01]", grow_for("[4국05-01]")[:standard_code], "3학년(g34)에게는 같은 코드가 허용 코드다"
  end

  test "the stored rubric of a reviewed report never keeps an out-of-band standard code" do
    @classroom.update!(grade: 6)
    response = review_response(grow: [ { "text" => "인물의 마음을 더 써 봐요", "standard_code" => "[4국05-01]" } ])
    service = Ai::ReviewService.new(client: StubClient.new(configured: true, response: response))

    @report.record_submission!
    stub_new(Ai::ReviewService, service) { perform_ai_review(@report) }

    assert_equal [ { "text" => "인물의 마음을 더 써 봐요", "standard_code" => "" } ], @report.reload.rubric["grow"]
  end

  # 외부 전송 최소화: 첨삭 요청이 Claude 로 실제 보내는 HTTP 본문(와이어)을 포착해, 학생을 알아볼 수
  # 있는 값(이름·이메일·닉네임·학교 이름·user id)이 없고 학생에게서 나온 내용은 책 제목과 본문뿐임을 확인한다.
  test "sends only the book title and body to Claude — no student name, email, nickname, school or user id" do
    school = School.create!(name: "개인정보확인초등학교")
    classroom = Classroom.create!(school: school, grade: 5, class_no: 3)
    student = User.create!(id: 987_654_321, school: school, classroom: classroom, name: "홍길순", password: "password",
                           email: "gilsoon.hong@example.com", nickname: "번개독서왕",
                           ai_consent: true, privacy_consent_at: Time.current)
    report = Report.create!(user: student, classroom: classroom, book_title: "강아지똥",
                            body: "강아지똥이 민들레를 도와준 장면이 감동적이었어요.")
    client, captured = capturing_claude_client(review_response)

    result = Ai::ReviewService.new(client: client).call(report)

    assert_equal "B", result[:level], "스텁 응답(LLM 경로)을 썼는지 확인"
    request = captured.fetch(:body)
    assert_equal %w[max_tokens messages model system], request.keys.sort, "metadata(user_id 등) 같은 추가 필드를 보내지 않는다"
    assert_equal [ { "role" => "user", "content" => [ { "type" => "text",
      "text" => "책 제목: 강아지똥\n\n독후감 본문:\n강아지똥이 민들레를 도와준 장면이 감동적이었어요." } ] } ],
      request["messages"], "학생에게서 나온 내용은 책 제목과 본문뿐이다"

    wire = captured.fetch(:raw)
    [ "홍길순", "gilsoon.hong@example.com", "번개독서왕", "개인정보확인초등학교", "987654321" ].each do |pii|
      assert_not_includes wire, pii, "Claude 요청에 #{pii} 가 들어가면 안 된다"
    end
    assert_empty captured.fetch(:headers).keys.map(&:downcase) - %w[x-api-key anthropic-version content-type user-agent],
                 "요청 헤더에도 학생 정보를 싣지 않는다"
  end

  private

  def review_response(grow: [])
    { "level" => "B", "rubric" => { "content" => 3, "emotion" => 3, "life" => 3, "structure" => 3, "spelling" => 3 },
      "praise" => [ "좋아요" ], "fix" => [], "grow" => grow, "pts" => 20 }
  end

  def grow_for(code, text: "성장 제안")
    response = review_response(grow: [ { "text" => text, "standard_code" => code } ])
    Ai::ReviewService.new(client: StubClient.new(configured: true, response: response)).call(@report.reload)[:grow].first
  end

  # 실제 Ai::ClaudeClient 에 Faraday 테스트 어댑터를 물려 **보내는 HTTP 요청**을 포착한다(claude_client_test 의
  # capture_request 와 같은 방식 — Faraday 가 env.body 를 응답으로 덮으므로 블록 안에서 복사해 둔다).
  def capturing_claude_client(response)
    captured = {}
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post(Ai::ClaudeClient::ENDPOINT) do |env|
        captured[:raw] = env.body.dup
        captured[:body] = JSON.parse(env.body)
        captured[:headers] = env.request_headers.dup
        [ 200, {}, { "type" => "message", "role" => "assistant",
                     "content" => [ { "type" => "text", "text" => response.to_json } ] }.to_json ]
      end
    end
    connection = Faraday.new { |faraday| faraday.adapter :test, stubs }
    [ Ai::ClaudeClient.new(api_key: "test-key", connection: connection), captured ]
  end

  # Minitest 6 에는 minitest/mock 이 없다 — `.new` 를 잠시 바꿔 주입한 인스턴스를 돌려준다(ai_review_job_test 와 같은 헬퍼).
  def stub_new(klass, replacement)
    klass.define_singleton_method(:new) { |*, **| replacement }
    yield
  ensure
    klass.singleton_class.send(:remove_method, :new)
  end

  def assert_valid_review(result)
    assert_includes %w[A B C], result[:level]
    assert_equal ReadingDomain::RUBRIC_AXES.sort, result[:rubric].keys.sort
    result[:rubric].each_value { |score| assert_includes 0..5, score }
    assert_includes ReadingDomain::LEVEL_POINTS.values, result[:pts]
    assert_kind_of Array, result[:grow]
  end
end
