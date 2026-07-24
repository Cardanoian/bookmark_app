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
            { "doc" => { "bookname" => "인기책", "isbn13" => "9781111111113", "loan_count" => "123" } },
            { "doc" => { "bookname" => "", "isbn13" => "9782222222224", "loan_count" => "5" } }
          ] }
        }.to_json ]
      end
    end
    service = Library::Data4libraryService.new(api_key: "KEY", connection: connection)

    loans = service.popular_loans

    assert_equal 1, loans.size, "빈 제목 문서는 제외돼야 한다"
    assert_equal "인기책", loans.first[:book_title]
    assert_equal "9781111111113", loans.first[:isbn]
    assert_equal 123, loans.first[:count]
  end

  test "popular_loans skips docs with a blank isbn13 (never emits a 0/empty row)" do
    connection = stub_connection do |stub|
      stub.get("/api/loanItemSrch") do
        [ 200, {}, {
          "response" => { "docs" => [
            { "doc" => { "bookname" => "정상책", "isbn13" => "9781111111113", "loan_count" => "10" } },
            { "doc" => { "bookname" => "isbn없는책", "isbn13" => "", "loan_count" => "9" } }
          ] }
        }.to_json ]
      end
    end
    service = Library::Data4libraryService.new(api_key: "KEY", connection: connection)

    loans = service.popular_loans

    assert_equal 1, loans.size, "isbn13 이 빈 문서는 제외돼야 한다"
    assert_equal "정상책", loans.first[:book_title]
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

  test "popular_loans passes age to the API when given (발견 학년군 인기도서)" do
    captured = {}
    connection = stub_connection do |stub|
      stub.get("/api/loanItemSrch") do |env|
        captured.merge!(Faraday::Utils.parse_query(env.url.query.to_s))
        [ 200, {}, { "response" => { "docs" => [] } }.to_json ]
      end
    end
    service = Library::Data4libraryService.new(api_key: "KEY", connection: connection)

    service.popular_loans(age: "a8")

    assert_equal "a8", captured["age"]
  end

  test "popular_loans omits age from the request when not given (하위호환, 기존 호출자 무회귀)" do
    captured = {}
    connection = stub_connection do |stub|
      stub.get("/api/loanItemSrch") do |env|
        captured.merge!(Faraday::Utils.parse_query(env.url.query.to_s))
        [ 200, {}, { "response" => { "docs" => [] } }.to_json ]
      end
    end
    service = Library::Data4libraryService.new(api_key: "KEY", connection: connection)

    service.popular_loans

    assert_not captured.key?("age"), "age 미지정 시 쿼리 파라미터 자체가 없어야 한다"
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

  # --- 도서 상세조회 표지 폴백(srchDtlList): 네이버 미색인 판본의 cover_url 공급 ---

  test "cover_url_for returns nil without a key (no network)" do
    service = Library::Data4libraryService.new(api_key: "")
    assert_nil service.cover_url_for("9788949140926")
  end

  test "cover_url_for returns nil for a blank isbn" do
    service = Library::Data4libraryService.new(api_key: "KEY")
    assert_nil service.cover_url_for("")
    assert_nil service.cover_url_for(nil)
  end

  test "cover_url_for extracts bookImageURL from srchDtlList detail" do
    captured = {}
    connection = stub_connection do |stub|
      stub.get("/api/srchDtlList") do |env|
        captured.merge!(Faraday::Utils.parse_query(env.url.query.to_s))
        [ 200, {}, {
          "response" => { "detail" => [
            { "book" => { "bookname" => "치폴리노의 모험", "isbn13" => "9788949140926",
                          "bookImageURL" => "https://img/chipollino.jpg" } }
          ] }
        }.to_json ]
      end
    end
    service = Library::Data4libraryService.new(api_key: "KEY", connection: connection)

    assert_equal "https://img/chipollino.jpg", service.cover_url_for("9788949140926")
    assert_equal "9788949140926", captured["isbn13"]
    assert_equal "N", captured["loaninfoYN"], "표지만 필요하므로 대출정보 조회를 생략한다"
  end

  test "cover_url_for returns nil when the book has no cover image (blank url)" do
    connection = stub_connection do |stub|
      stub.get("/api/srchDtlList") do
        [ 200, {}, { "response" => { "detail" => [ { "book" => { "bookImageURL" => "" } } ] } }.to_json ]
      end
    end
    service = Library::Data4libraryService.new(api_key: "KEY", connection: connection)
    assert_nil service.cover_url_for("9788949140926")
  end

  test "cover_url_for returns nil when detail is empty (book not found)" do
    connection = stub_connection do |stub|
      stub.get("/api/srchDtlList") { [ 200, {}, { "response" => { "detail" => [] } }.to_json ] }
    end
    service = Library::Data4libraryService.new(api_key: "KEY", connection: connection)
    assert_nil service.cover_url_for("9788949140926")
  end

  test "cover_url_for returns nil on a non-200 response" do
    connection = stub_connection { |stub| stub.get("/api/srchDtlList") { [ 500, {}, "err" ] } }
    service = Library::Data4libraryService.new(api_key: "KEY", connection: connection)
    assert_nil service.cover_url_for("9788949140926")
  end

  test "cover_url_for returns nil on malformed JSON" do
    connection = stub_connection { |stub| stub.get("/api/srchDtlList") { [ 200, {}, "not json" ] } }
    service = Library::Data4libraryService.new(api_key: "KEY", connection: connection)
    assert_nil service.cover_url_for("9788949140926")
  end

  test "cover_url_for does not clobber popular_loans last_error" do
    connection = stub_connection { |stub| stub.get("/api/srchDtlList") { [ 500, {}, "err" ] } }
    service = Library::Data4libraryService.new(api_key: "KEY", connection: connection)

    service.cover_url_for("9788949140926")
    assert_nil service.last_error, "cover_url_for 는 popular_loans 의 last_error 를 오염시키지 않는다"
  end

  # --- 인근 도서관 소장 조회(libSrchByBook): response.libs[].lib 정규화, 실패=nil ---

  test "libraries_holding returns [] without a key (no network)" do
    service = Library::Data4libraryService.new(api_key: "")
    assert_equal [], service.libraries_holding(isbn13: "9788949140926", region: "11")
  end

  test "libraries_holding returns [] for a blank isbn or region" do
    service = Library::Data4libraryService.new(api_key: "KEY")
    assert_equal [], service.libraries_holding(isbn13: "", region: "11")
    assert_equal [], service.libraries_holding(isbn13: "9788949140926", region: "")
  end

  test "libraries_holding normalizes response.libs[].lib (note nesting differs from docs[].doc)" do
    captured = {}
    connection = stub_connection do |stub|
      stub.get("/api/libSrchByBook") do |env|
        captured.merge!(Faraday::Utils.parse_query(env.url.query.to_s))
        [ 200, {}, {
          "response" => { "numFound" => 2, "libs" => [
            { "lib" => { "libCode" => "111001", "libName" => "노원구립도서관",
                         "address" => "서울특별시 노원구 상계로 1", "tel" => "02-1", "homepage" => "https://a.kr",
                         "latitude" => "37.6", "longitude" => "127.0" } },
            { "lib" => { "libCode" => "111002", "libName" => "월계도서관",
                         "address" => "서울특별시 노원구 월계로 2", "homepage" => "" } }
          ] }
        }.to_json ]
      end
    end
    service = Library::Data4libraryService.new(api_key: "KEY", connection: connection)

    libs = service.libraries_holding(isbn13: "9788949140926", region: "11", page_size: 500)

    assert_equal 2, libs.size
    assert_equal "111001", libs.first[:code]
    assert_equal "노원구립도서관", libs.first[:name]
    assert_equal "서울특별시 노원구 상계로 1", libs.first[:address]
    assert_equal "https://a.kr", libs.first[:homepage]
    assert_equal "9788949140926", captured["isbn"]
    assert_equal "11", captured["region"]
    assert_equal "500", captured["pageSize"]
  end

  test "libraries_holding returns [] on an empty result (book held nowhere)" do
    connection = stub_connection do |stub|
      stub.get("/api/libSrchByBook") { [ 200, {}, { "response" => { "libs" => [] } }.to_json ] }
    end
    service = Library::Data4libraryService.new(api_key: "KEY", connection: connection)
    assert_equal [], service.libraries_holding(isbn13: "9788949140926", region: "11")
  end

  test "libraries_holding returns nil on a non-200 response (distinguishes error from empty)" do
    connection = stub_connection { |stub| stub.get("/api/libSrchByBook") { [ 500, {}, "err" ] } }
    service = Library::Data4libraryService.new(api_key: "KEY", connection: connection)
    assert_nil service.libraries_holding(isbn13: "9788949140926", region: "11")
  end

  test "libraries_holding returns nil on malformed JSON" do
    connection = stub_connection { |stub| stub.get("/api/libSrchByBook") { [ 200, {}, "not json" ] } }
    service = Library::Data4libraryService.new(api_key: "KEY", connection: connection)
    assert_nil service.libraries_holding(isbn13: "9788949140926", region: "11")
  end

  test "libraries_holding warns but still returns rows when numFound exceeds page_size" do
    connection = stub_connection do |stub|
      stub.get("/api/libSrchByBook") do
        [ 200, {}, {
          "response" => { "numFound" => 999, "libs" => [
            { "lib" => { "libCode" => "1", "libName" => "관", "address" => "서울특별시 노원구 로 1" } }
          ] }
        }.to_json ]
      end
    end
    service = Library::Data4libraryService.new(api_key: "KEY", connection: connection)

    assert_equal 1, service.libraries_holding(isbn13: "9788949140926", region: "11", page_size: 100).size
  end

  test "libraries_holding does not clobber popular_loans last_error" do
    connection = stub_connection { |stub| stub.get("/api/libSrchByBook") { [ 500, {}, "err" ] } }
    service = Library::Data4libraryService.new(api_key: "KEY", connection: connection)

    service.libraries_holding(isbn13: "9788949140926", region: "11")
    assert_nil service.last_error
  end

  # --- 도서관별 대출여부(bookExist): loanAvailable Y/N/에러 → status + fetched_at ---

  test "loan_status returns :unknown without a key (no network)" do
    service = Library::Data4libraryService.new(api_key: "")
    status = service.loan_status(lib_code: "111001", isbn13: "9788949140926")
    assert_equal :unknown, status[:status]
    assert_kind_of Time, status[:fetched_at]
  end

  test "loan_status maps loanAvailable Y to :available and N to :unavailable" do
    connection = stub_connection do |stub|
      stub.get("/api/bookExist") do |env|
        params = Faraday::Utils.parse_query(env.url.query.to_s)
        available = params["libCode"] == "AVAIL" ? "Y" : "N"
        [ 200, {}, { "response" => { "result" => { "hasBook" => "Y", "loanAvailable" => available } } }.to_json ]
      end
    end
    service = Library::Data4libraryService.new(api_key: "KEY", connection: connection)

    assert_equal :available, service.loan_status(lib_code: "AVAIL", isbn13: "9788949140926")[:status]
    assert_equal :unavailable, service.loan_status(lib_code: "BUSY", isbn13: "9788949140926")[:status]
  end

  test "loan_status returns :unknown on a non-200 response (never crashes)" do
    connection = stub_connection { |stub| stub.get("/api/bookExist") { [ 500, {}, "err" ] } }
    service = Library::Data4libraryService.new(api_key: "KEY", connection: connection)
    assert_equal :unknown, service.loan_status(lib_code: "111001", isbn13: "9788949140926")[:status]
  end

  test "loan_status returns :unknown on malformed JSON" do
    connection = stub_connection { |stub| stub.get("/api/bookExist") { [ 200, {}, "not json" ] } }
    service = Library::Data4libraryService.new(api_key: "KEY", connection: connection)
    assert_equal :unknown, service.loan_status(lib_code: "111001", isbn13: "9788949140926")[:status]
  end

  test "loan_status uses a shorter read timeout for the bookExist fan-out" do
    captured_timeout = nil
    connection = stub_connection do |stub|
      stub.get("/api/bookExist") do |env|
        captured_timeout = env.request.timeout
        [ 200, {}, { "response" => { "result" => { "loanAvailable" => "Y" } } }.to_json ]
      end
    end
    service = Library::Data4libraryService.new(api_key: "KEY", connection: connection)

    service.loan_status(lib_code: "111001", isbn13: "9788949140926")
    assert_equal Library::Data4libraryService::BOOK_EXIST_READ_TIMEOUT, captured_timeout
  end

  test "loan_status does not clobber popular_loans last_error" do
    connection = stub_connection { |stub| stub.get("/api/bookExist") { [ 500, {}, "err" ] } }
    service = Library::Data4libraryService.new(api_key: "KEY", connection: connection)

    service.loan_status(lib_code: "111001", isbn13: "9788949140926")
    assert_nil service.last_error
  end
end
