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

  test "falls back without calling Claude for an author without AI consent (P1-1)" do
    non_consenting = User.create!(school: @school, classroom: @classroom, name: "미동의코멘트학생", password: "password")
    sequel = BookSequel.create!(user: non_consenting, book: @book, classroom: @classroom,
                                body: "새로운 세계로 떠나는 뒷이야기를 상상했어요.")
    called = false
    client = StubClient.new(configured: true)
    client.define_singleton_method(:generate) { |**| called = true; { "comment" => "x" } }

    comment = Ai::SequelFeedbackService.new(client: client).call(sequel)

    assert_not called, "미동의 학생 창작글은 Claude 로 보내지 않는다"
    assert comment.present?
  end

  test "falls back on ApiError" do
    client = StubClient.new(configured: true, error: Ai::ClaudeClient::ApiError.new("boom"))
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

  # 외부 전송 최소화: 격려 코멘트 요청도 실제 HTTP 본문을 포착해, 학생을 알아볼 수 있는 값(이름·이메일·
  # 닉네임·학교 이름·user id)이 없고 학생에게서 나온 내용은 뒷이야기 본문뿐임을 확인한다(책 제목·지은이는 맥락).
  test "sends only the book context and story body to Claude — no student name, email, nickname, school or user id" do
    school = School.create!(name: "뒷이야기개인정보초등학교")
    classroom = Classroom.create!(school: school, grade: 4, class_no: 2)
    author = User.create!(id: 987_654_322, school: school, classroom: classroom, name: "김다온", password: "password",
                          email: "daon.kim@example.com", nickname: "상상대장",
                          ai_consent: true, privacy_consent_at: Time.current)
    sequel = BookSequel.create!(user: author, book: @book, classroom: classroom,
                                body: "강아지똥은 봄이 오자 민들레 친구들과 소풍을 떠났어요.")
    captured = {}
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post(Ai::ClaudeClient::ENDPOINT) do |env|
        captured[:raw] = env.body.dup # Faraday 가 env.body 를 응답으로 덮으므로 블록 안에서 복사한다.
        captured[:body] = JSON.parse(env.body)
        [ 200, {}, { "type" => "message", "role" => "assistant",
                     "content" => [ { "type" => "text", "text" => { comment: "좋아요" }.to_json } ] }.to_json ]
      end
    end
    client = Ai::ClaudeClient.new(api_key: "test-key", connection: Faraday.new { |f| f.adapter :test, stubs })

    assert_equal "좋아요", Ai::SequelFeedbackService.new(client: client).call(sequel), "스텁 응답(LLM 경로)을 썼는지 확인"

    assert_equal %w[max_tokens messages model system], captured[:body].keys.sort, "metadata(user_id 등)를 보내지 않는다"
    assert_equal "책 제목: 코멘트책\n지은이: 지은이\n\n학생이 이어 쓴 뒷이야기:\n#{sequel.body}",
                 captured[:body]["messages"].sole["content"].sole["text"]
    [ "김다온", "daon.kim@example.com", "상상대장", "뒷이야기개인정보초등학교", "987654322" ].each do |pii|
      assert_not_includes captured[:raw], pii, "Claude 요청에 #{pii} 가 들어가면 안 된다"
    end
  end

  # 베타 리뷰: '테스트테스트…'에 "뒷이야기를 이어 쓰고 싶었던 마음이 잘 전해져요"라고 칭찬했다.
  # 뒷이야기가 아닌 글은 칭찬 없이 1~2문장으로 진짜 이어쓰기를 부탁해야 한다(서툰 진짜 글은 예외).
  test "system instruction refuses to praise non-stories and asks for a real continuation" do
    prompt = Ai::SequelFeedbackService::SYSTEM_INSTRUCTION

    assert_includes prompt, "자음·모음만 늘어놓은 글"
    assert_includes prompt, "'테스트테스트테스트'"
    assert_includes prompt, "뒷이야기가 아니면 칭찬하지 않는다"
    assert_includes prompt, "글에 없는 마음이나 노력을 짐작해서 칭찬하지도 않는다"
    assert_includes prompt, "1~2문장으로, 이야기가 어떻게 이어질지 직접 써 달라고"
    assert_includes prompt, "이야기를 이어 쓰려고 한 흔적이 있으면 뒷이야기로 보고"
  end

  # 말투(호칭 금지·해요체)와 책 내용 단정 금지는 첨삭 프롬프트와 같은 규칙을 공유한다.
  test "system instruction shares the child voice and book-fact rules with the review prompt" do
    prompt = Ai::SequelFeedbackService::SYSTEM_INSTRUCTION

    assert_includes prompt, ReadingDomain::CHILD_VOICE_RULES
    assert_includes prompt, ReadingDomain::BOOK_FACT_RULES
    assert_includes prompt, "'당신'"
    assert_includes prompt, "해요체로만"
    assert_includes prompt, "작은따옴표(' ') 안에 한 글자도 바꾸지 말고 그대로"
    assert_includes prompt, "점수·등급·별점을 절대 매기지 않는다"
    assert_includes prompt, '{"comment": "<격려 코멘트>"}', "응답 스키마 불변"
  end
end
