require "test_helper"

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

  # 동기 웹요청 경로의 스레드 고갈을 막기 위해 실 Faraday 연결에 타임아웃을 설정한다(§0.4).
  test "real connection is configured with http timeouts (open 3s / read 8s)" do
    connection = Ai::GeminiClient.new.send(:connection)
    assert_equal 3, connection.options.open_timeout
    assert_equal 8, connection.options.timeout
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
