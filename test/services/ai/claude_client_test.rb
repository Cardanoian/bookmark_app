require "test_helper"

class Ai::ClaudeClientTest < ActiveSupport::TestCase
  test "raises NotConfigured when the api key is blank" do
    client = Ai::ClaudeClient.new(api_key: "")
    assert_raises(Ai::ClaudeClient::NotConfigured) do
      client.generate(contents: [])
    end
  end

  test "available? is false without a key (blank credentials in test)" do
    assert_not Ai::ClaudeClient.available?
  end

  test "configured? is true with a key" do
    assert Ai::ClaudeClient.new(api_key: "test-key").configured?
  end

  test "generate parses JSON out of the assistant text block" do
    inner = { "hello" => "world", "n" => 1 }
    client = build_client { |stub| stub.post(Ai::ClaudeClient::ENDPOINT) { [ 200, {}, message_payload(inner.to_json) ] } }

    assert_equal inner, client.generate(contents: [ { role: "user", parts: [ { text: "hi" } ] } ])
  end

  # Anthropic 에는 Gemini 의 responseMimeType 같은 JSON 강제 스위치가 없어, "JSON 만 반환"을
  # 요구해도 모델이 코드펜스를 두를 수 있다. 펜스는 폴백 사유가 아니라 벗겨서 통과시켜야 한다.
  test "generate strips a markdown code fence before parsing" do
    inner = { "level" => "B" }
    fenced = "```json\n#{inner.to_json}\n```"
    client = build_client { |stub| stub.post(Ai::ClaudeClient::ENDPOINT) { [ 200, {}, message_payload(fenced) ] } }

    assert_equal inner, client.generate(contents: [])
  end

  # 펜스가 아니라 앞뒤에 인사말이 붙은 경우도 첫 여는 괄호~마지막 닫는 괄호를 건져 한 번 더 시도한다.
  test "generate salvages JSON surrounded by prose" do
    inner = { "ok" => true }
    noisy = "네, 결과입니다.\n#{inner.to_json}\n도움이 되었길 바랍니다."
    client = build_client { |stub| stub.post(Ai::ClaudeClient::ENDPOINT) { [ 200, {}, message_payload(noisy) ] } }

    assert_equal inner, client.generate(contents: [])
  end

  test "raises ApiError on a non-2xx response" do
    client = build_client { |stub| stub.post(Ai::ClaudeClient::ENDPOINT) { [ 500, {}, "server error" ] } }

    assert_raises(Ai::ClaudeClient::ApiError) do
      client.generate(contents: [])
    end
  end

  test "raises ApiError when the text block is not valid JSON" do
    client = build_client { |stub| stub.post(Ai::ClaudeClient::ENDPOINT) { [ 200, {}, message_payload("not json at all") ] } }

    assert_raises(Ai::ClaudeClient::ApiError) do
      client.generate(contents: [])
    end
  end

  test "raises ApiError when the response carries no text block" do
    payload = { "content" => [] }.to_json
    client = build_client { |stub| stub.post(Ai::ClaudeClient::ENDPOINT) { [ 200, {}, payload ] } }

    assert_raises(Ai::ClaudeClient::ApiError) do
      client.generate(contents: [])
    end
  end

  # Anthropic 필수 헤더·필수 파라미터 회귀 가드: anthropic-version 이 빠지거나 max_tokens 가
  # 없으면 실서버가 400 을 낸다(Gemini 에는 둘 다 없던 요구사항이라 이관 때 빠뜨리기 쉽다).
  test "request carries the required auth/version headers and a max_tokens" do
    captured = capture_request(contents: [])

    assert_equal "test-key", captured[:headers]["x-api-key"]
    assert_equal Ai::ClaudeClient::API_VERSION, captured[:headers]["anthropic-version"]
    assert_equal Ai::ClaudeClient::MODEL, captured[:body]["model"]
    assert_equal Ai::ClaudeClient::DEFAULT_MAX_TOKENS, captured[:body]["max_tokens"]
  end

  # 제공자 중립 contents(Gemini 시절 형태)를 Anthropic messages 로 옮기는 어댑터가 이 클래스의
  # 존재 이유다. 텍스트 파트·이미지 파트(OCR)·systemInstruction 세 갈래를 모두 덮는다.
  test "translates neutral contents into anthropic messages including image parts" do
    contents = [ {
      role: "user",
      parts: [
        { text: "손글씨를 읽어 주세요" },
        { inlineData: { mimeType: "image/jpeg", data: "BASE64DATA" } }
      ]
    } ]
    captured = capture_request(contents: contents, system_instruction: "너는 국어 선생님이다")

    assert_equal "너는 국어 선생님이다", captured[:body]["system"]
    assert_equal 1, captured[:body]["messages"].size

    message = captured[:body]["messages"].first
    assert_equal "user", message["role"]
    assert_equal({ "type" => "text", "text" => "손글씨를 읽어 주세요" }, message["content"][0])
    assert_equal(
      { "type" => "image", "source" => { "type" => "base64", "media_type" => "image/jpeg", "data" => "BASE64DATA" } },
      message["content"][1]
    )
  end

  # 옛 Gemini Content 해시({ parts: [{ text: }] })로 system_instruction 이 들어와도 문자열로 눕힌다.
  test "accepts a legacy Content-hash system instruction" do
    captured = capture_request(contents: [], system_instruction: { parts: [ { text: "시스템 지시" } ] })

    assert_equal "시스템 지시", captured[:body]["system"]
  end

  # 실 Faraday 연결에 타임아웃을 설정해 스레드 고갈을 막는다(§0.4).
  test "real connection is configured with http timeouts (open 3s / read 30s)" do
    connection = Ai::ClaudeClient.new.send(:connection)
    assert_equal 3, connection.options.open_timeout
    assert_equal 30, connection.options.timeout
  end

  # Messages 호출(POST)에 Anthropic 의 일시 실패 상태코드(429/500/529)와 타임아웃 재시도가
  # 타이트한 상한으로 걸려 있는지 확인한다(§2.4).
  test "real connection registers a bounded retry middleware for transient 429/500/529/timeout failures" do
    connection = Ai::ClaudeClient.new.send(:connection)
    handler = connection.builder.handlers.find { |h| h.klass <= Faraday::Retry::Middleware }
    assert handler, "retry 미들웨어가 등록돼 있어야 한다"

    options = handler.build(->(env) { env }).instance_variable_get(:@options)
    assert_equal 2, options.max
    assert_equal [ 429, 500, 529 ], options.retry_statuses
    assert_includes options.methods, :post, "messages 는 POST 라서 명시적으로 포함돼야 재시도된다"
    assert_includes options.exceptions, Faraday::TimeoutError
    assert_includes options.exceptions, Faraday::ConnectionFailed
  end

  private

  # Anthropic Messages 응답 봉투: content 블록 배열에서 text 블록만 이어 붙인다.
  def message_payload(text)
    { "id" => "msg_test", "type" => "message", "role" => "assistant",
      "content" => [ { "type" => "text", "text" => text } ],
      "stop_reason" => "end_turn" }.to_json
  end

  # Faraday 는 env 를 in-place 로 재사용해, 응답이 오면 env.body 가 **응답** 본문으로 덮인다.
  # 그래서 env 객체를 블록 밖으로 들고 나오면 요청 본문을 볼 수 없다 — 블록 안에서 복사해 둔다.
  def capture_request(**generate_args)
    captured = {}
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post(Ai::ClaudeClient::ENDPOINT) do |env|
        captured[:body] = JSON.parse(env.body)
        captured[:headers] = env.request_headers.dup
        [ 200, {}, message_payload({ ok: 1 }.to_json) ]
      end
    end
    connection = Faraday.new { |faraday| faraday.adapter :test, stubs }
    Ai::ClaudeClient.new(api_key: "test-key", connection: connection).generate(**generate_args)
    captured
  end

  def build_client(&block)
    stubs = Faraday::Adapter::Test::Stubs.new(&block)
    connection = Faraday.new { |faraday| faraday.adapter :test, stubs }
    Ai::ClaudeClient.new(api_key: "test-key", connection: connection)
  end
end
