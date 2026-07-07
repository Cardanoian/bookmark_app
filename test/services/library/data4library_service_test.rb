require "test_helper"

# P6.5 정보나루(data4library) 서비스: 무키 → 사용불가/빈 배열, 스텁 연결 → 정규화·파싱.
class Library::Data4libraryServiceTest < ActiveSupport::TestCase
  # 스텁 Faraday 연결(네트워크 차단).
  def stub_connection(&block)
    stubs = Faraday::Adapter::Test::Stubs.new(&block)
    Faraday.new { |faraday| faraday.adapter :test, stubs }
  end

  test "BASE_URL uses https (authKey travels over TLS)" do
    assert_equal "https://data4library.kr", Library::Data4libraryService::BASE_URL
  end

  test "available? is false when the api key is blank (placeholder credential)" do
    assert_not Library::Data4libraryService.new(api_key: "").available?
  end

  test "available? is true when a key is present" do
    assert Library::Data4libraryService.new(api_key: "KEY").available?
  end

  test "popular_loans returns [] without a key (no network, CSV fallback)" do
    service = Library::Data4libraryService.new(api_key: "")
    assert_equal [], service.popular_loans
  end

  test "popular_loans normalizes docs from a stubbed response" do
    connection = stub_connection do |stub|
      stub.get("/api/loanItemSrch") do
        [ 200, {}, {
          "response" => { "docs" => [
            { "doc" => { "bookname" => "인기책", "isbn13" => "9781111111111", "loan_count" => "123" } },
            { "doc" => { "bookname" => "", "isbn13" => "9782222222222", "loan_count" => "5" } }
          ] }
        }.to_json ]
      end
    end
    service = Library::Data4libraryService.new(api_key: "KEY", connection: connection)

    loans = service.popular_loans

    assert_equal 1, loans.size, "빈 제목 문서는 제외돼야 한다"
    assert_equal "인기책", loans.first[:book_title]
    assert_equal "9781111111111", loans.first[:isbn]
    assert_equal 123, loans.first[:count]
  end

  test "popular_loans returns [] on a non-200 response (never crashes)" do
    connection = stub_connection { |stub| stub.get("/api/loanItemSrch") { [ 500, {}, "err" ] } }
    service = Library::Data4libraryService.new(api_key: "KEY", connection: connection)
    assert_equal [], service.popular_loans
  end

  test "popular_loans returns [] on malformed JSON" do
    connection = stub_connection { |stub| stub.get("/api/loanItemSrch") { [ 200, {}, "not json" ] } }
    service = Library::Data4libraryService.new(api_key: "KEY", connection: connection)
    assert_equal [], service.popular_loans
  end

  test "popular_loans passes the date range to the API (startDt/endDt)" do
    captured = {}
    connection = stub_connection do |stub|
      stub.get("/api/loanItemSrch") do |env|
        captured.merge!(Faraday::Utils.parse_query(env.url.query.to_s))
        [ 200, {}, { "response" => { "docs" => [] } }.to_json ]
      end
    end
    service = Library::Data4libraryService.new(api_key: "KEY", connection: connection)

    service.popular_loans(from: "2026-06-01", to: "2026-06-30")

    assert_equal "2026-06-01", captured["startDt"]
    assert_equal "2026-06-30", captured["endDt"]
  end

  test "last_error stays nil after a successful sync (distinguishes empty from failure)" do
    connection = stub_connection do |stub|
      stub.get("/api/loanItemSrch") { [ 200, {}, { "response" => { "docs" => [] } }.to_json ] }
    end
    service = Library::Data4libraryService.new(api_key: "KEY", connection: connection)

    assert_equal [], service.popular_loans
    assert_nil service.last_error, "빈 결과(성공)는 실패가 아니어야 한다"
  end

  test "last_error is set on a non-200 response" do
    connection = stub_connection { |stub| stub.get("/api/loanItemSrch") { [ 500, {}, "err" ] } }
    service = Library::Data4libraryService.new(api_key: "KEY", connection: connection)

    service.popular_loans
    assert_not_nil service.last_error
  end

  test "last_error is set on malformed JSON" do
    connection = stub_connection { |stub| stub.get("/api/loanItemSrch") { [ 200, {}, "not json" ] } }
    service = Library::Data4libraryService.new(api_key: "KEY", connection: connection)

    service.popular_loans
    assert_not_nil service.last_error
  end

  # 동기 웹요청 경로(정보나루 대출)의 스레드 고갈을 막기 위해 실 Faraday 연결에 타임아웃을 설정한다(§0.4).
  test "real connection is configured with http timeouts (open 3s / read 8s)" do
    connection = Library::Data4libraryService.new(api_key: "KEY").send(:connection)
    assert_equal 3, connection.options.open_timeout
    assert_equal 8, connection.options.timeout
  end
end
