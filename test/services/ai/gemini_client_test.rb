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

  private

  def build_client(&block)
    stubs = Faraday::Adapter::Test::Stubs.new(&block)
    connection = Faraday.new { |faraday| faraday.adapter :test, stubs }
    Ai::GeminiClient.new(api_key: "test-key", connection: connection)
  end
end
