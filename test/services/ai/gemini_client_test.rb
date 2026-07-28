require "test_helper"

# Gemini 클라이언트는 **손글씨 OCR 전용**이다(나머지 AI 는 Ai::ClaudeClient). 그래서 이 테스트도
# OCR 경로가 의존하는 계약만 못 박는다 — JSON 파싱·실패 시 ApiError·타임아웃·재시도.
class Ai::GeminiClientTest < ActiveSupport::TestCase
  test "raises NotConfigured when the api key is blank" do
    client = Ai::GeminiClient.new(api_key: "")
    assert_raises(Ai::GeminiClient::NotConfigured) do
      client.generate(contents: [])
    end
  end

  test "available? is false without a key (blank credentials in test)" do
    assert_not Ai::GeminiClient.available?
  end

  test "configured? is true with a key" do
    assert Ai::GeminiClient.new(api_key: "test-key").configured?
  end

  test "generate parses candidate JSON text from an injected connection" do
    inner = { "hello" => "world", "n" => 1 }
    payload = { "candidates" => [ { "content" => { "parts" => [ { "text" => inner.to_json } ] } } ] }
    client = build_client { |stub| stub.post(Ai::GeminiClient::ENDPOINT) { [ 200, {}, payload.to_json ] } }

    assert_equal inner, client.generate(contents: [ { role: "user", parts: [ { text: "hi" } ] } ])
  end

  test "raises ApiError on a non-200 response" do
    client = build_client { |stub| stub.post(Ai::GeminiClient::ENDPOINT) { [ 500, {}, "server error" ] } }

    assert_raises(Ai::GeminiClient::ApiError) do
      client.generate(contents: [])
    end
  end

  test "raises ApiError when the candidate text is not valid JSON" do
    payload = { "candidates" => [ { "content" => { "parts" => [ { "text" => "not json at all" } ] } } ] }
    client = build_client { |stub| stub.post(Ai::GeminiClient::ENDPOINT) { [ 200, {}, payload.to_json ] } }

    assert_raises(Ai::GeminiClient::ApiError) do
      client.generate(contents: [])
    end
  end

  # OCR 은 이 클라이언트가 responseMimeType 을 JSON 으로 강제하는 데 기대어 {"text": ...} 를 받는다.
  # 엔드포인트에 박힌 모델도 함께 확인한다 — 모델을 바꾸면 URL 이 바뀌므로 회귀가 조용하지 않게.
  test "request forces JSON response mime type and targets the OCR model endpoint" do
    captured = nil
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post(Ai::GeminiClient::ENDPOINT) do |env|
        captured = JSON.parse(env.body)
        [ 200, {}, { "candidates" => [ { "content" => { "parts" => [ { "text" => "{}" } ] } } ] }.to_json ]
      end
    end
    connection = Faraday.new { |faraday| faraday.adapter :test, stubs }

    Ai::GeminiClient.new(api_key: "test-key", connection: connection)
      .generate(contents: [ { role: "user", parts: [ { text: "hi" } ] } ])

    assert_equal "application/json", captured.dig("generationConfig", "responseMimeType")
    assert_equal "gemini-3.5-flash-lite", Ai::GeminiClient::MODEL
    assert_includes Ai::GeminiClient::ENDPOINT, Ai::GeminiClient::MODEL
  end

  # 실 Faraday 연결에 타임아웃을 설정해 스레드 고갈을 막는다(§0.4). read 타임아웃은 손글씨 OCR
  # 실측 지연(2.5~4.4s)에 재시도·긴 원고까지 얹어 30s 로 둔다 — 과거 8s 는 매 시도를 타임아웃시켰다.
  test "real connection is configured with http timeouts (open 3s / read 30s)" do
    connection = Ai::GeminiClient.new.send(:connection)
    assert_equal 3, connection.options.open_timeout
    assert_equal 30, connection.options.timeout
  end

  # generateContent 호출(POST)에 429/503·타임아웃에 대한 재시도가 타이트한 상한으로 걸려 있는지 확인한다(§2.4).
  test "real connection registers a bounded retry middleware for transient 429/503/timeout failures" do
    connection = Ai::GeminiClient.new.send(:connection)
    handler = connection.builder.handlers.find { |h| h.klass <= Faraday::Retry::Middleware }
    assert handler, "retry 미들웨어가 등록돼 있어야 한다"

    options = handler.build(->(env) { env }).instance_variable_get(:@options)
    assert_equal 2, options.max
    assert_equal [ 429, 503 ], options.retry_statuses
    assert_includes options.methods, :post, "generateContent 은 POST 라서 명시적으로 포함돼야 재시도된다"
    assert_includes options.exceptions, Faraday::TimeoutError
    assert_includes options.exceptions, Faraday::ConnectionFailed
  end

  private

  def build_client(&block)
    stubs = Faraday::Adapter::Test::Stubs.new(&block)
    connection = Faraday.new { |faraday| faraday.adapter :test, stubs }
    Ai::GeminiClient.new(api_key: "test-key", connection: connection)
  end
end
