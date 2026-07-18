require "test_helper"

# NEIS 학교기본정보 페처 단위 테스트(계획 §1.2). 스텁 Faraday 연결로 네트워크를 차단하고
# 필드 매핑·gu 파싱·완전한 페이지네이션·무키 폴백을 검증한다(SearchService DI 패턴).
class Schools::NeisFetcherTest < ActiveSupport::TestCase
  def stub_connection(&block)
    stubs = Faraday::Adapter::Test::Stubs.new(&block)
    Faraday.new { |faraday| faraday.adapter :test, stubs }
  end

  def neis_body(rows, total_count: rows.size, code: "INFO-000")
    {
      "schoolInfo" => [
        { "head" => [ { "list_total_count" => total_count }, { "RESULT" => { "CODE" => code, "MESSAGE" => "처리 결과" } } ] },
        { "row" => rows }
      ]
    }.to_json
  end

  def neis_row(code:, name:, kind: "초등학교", region: "서울특별시교육청", office: "B10", addr: "서울특별시 강남구 언주로 3")
    {
      "SD_SCHUL_CODE" => code, "SCHUL_NM" => name, "SCHUL_KND_SC_NM" => kind,
      "ATPT_OFCDC_SC_NM" => region, "ATPT_OFCDC_SC_CODE" => office, "ORG_RDNMA" => addr
    }
  end

  test "available? is false when the NEIS key is blank" do
    assert_not Schools::NeisFetcher.new(api_key: "").available?
    assert_equal [], Schools::NeisFetcher.new(api_key: "").fetch_all
  end

  test "maps NEIS fields and parses gu" do
    connection = stub_connection do |stub|
      stub.get("/hub/schoolInfo") do
        [ 200, {}, neis_body([
          neis_row(code: "S1", name: "서울강남초", region: "서울특별시교육청", office: "B10", addr: "서울특별시 강남구 언주로 3")
        ]) ]
      end
    end
    fetcher = Schools::NeisFetcher.new(api_key: "K", connection: connection)

    rows = fetcher.fetch_all

    assert_equal 1, rows.size
    row = rows.first
    assert_equal "S1", row[:neis_code]
    assert_equal "서울강남초", row[:name]
    assert_equal "서울특별시교육청", row[:region]
    assert_equal "강남구", row[:gu]
    assert_equal "B10", row[:office_code]
    assert_equal "서울특별시 강남구 언주로 3", row[:address]
  end

  test "drops non-elementary, uncoded planned, and overseas rows after complete collection" do
    connection = stub_connection do |stub|
      stub.get("/hub/schoolInfo") do
        [ 200, {}, neis_body([
          neis_row(code: "S1", name: "정상초"),
          neis_row(code: "M1", name: "중학교아님", kind: "중학교"),
          neis_row(code: "", name: "개교예정초"),
          neis_row(code: "O1", name: "재외초", office: "V10", region: "재외한국학교교육청")
        ]) ]
      end
    end

    rows = Schools::NeisFetcher.new(api_key: "K", connection: connection, max_attempts: 1).fetch_all

    assert_equal [ "S1" ], rows.pluck(:neis_code)
  end

  test "세종 학교의 gu 는 nil(단층제)" do
    connection = stub_connection do |stub|
      stub.get("/hub/schoolInfo") do
        [ 200, {}, neis_body([
          neis_row(code: "SJ1", name: "세종한솔초", region: "세종특별자치시교육청", office: "I10", addr: "세종특별자치시 한누리대로 2154")
        ]) ]
      end
    end
    fetcher = Schools::NeisFetcher.new(api_key: "K", connection: connection)

    assert_nil fetcher.fetch_all.first[:gu]
  end

  test "paginates until the API total count is collected" do
    page1 = Array.new(Schools::NeisFetcher::PAGE_SIZE) { |i| neis_row(code: "P1#{i}", name: "초등#{i}") }
    page2 = [ neis_row(code: "P2", name: "막초등") ]
    connection = stub_connection do |stub|
      stub.get("/hub/schoolInfo") do |env|
        rows = env.params["pIndex"].to_i == 1 ? page1 : page2
        [ 200, {}, neis_body(rows, total_count: Schools::NeisFetcher::PAGE_SIZE + 1) ]
      end
    end
    fetcher = Schools::NeisFetcher.new(api_key: "K", connection: connection)

    result = fetcher.fetch_all

    assert_equal Schools::NeisFetcher::PAGE_SIZE + 1, result.size
    assert_equal "P2", result.last[:neis_code]
  end

  test "raises on a server error so callers preserve the previous snapshot" do
    connection = stub_connection { |stub| stub.get("/hub/schoolInfo") { [ 500, {}, "error" ] } }
    fetcher = Schools::NeisFetcher.new(api_key: "K", connection: connection, max_attempts: 1)

    assert_raises(Schools::NeisFetcher::FetchError) { fetcher.fetch_all }
  end

  test "raises instead of returning a partial snapshot when a later page fails" do
    page1 = Array.new(Schools::NeisFetcher::PAGE_SIZE) { |i| neis_row(code: "P1#{i}", name: "초등#{i}") }
    connection = stub_connection do |stub|
      stub.get("/hub/schoolInfo") do |env|
        if env.params["pIndex"].to_i == 1
          [ 200, {}, neis_body(page1, total_count: Schools::NeisFetcher::PAGE_SIZE + 1) ]
        else
          [ 500, {}, "error" ]
        end
      end
    end

    assert_raises(Schools::NeisFetcher::FetchError) do
      Schools::NeisFetcher.new(api_key: "K", connection: connection, max_attempts: 1).fetch_all
    end
  end

  test "raises on an API error delivered with HTTP 200" do
    connection = stub_connection do |stub|
      stub.get("/hub/schoolInfo") { [ 200, {}, neis_body([], total_count: 0, code: "ERROR-300") ] }
    end

    assert_raises(Schools::NeisFetcher::FetchError) do
      Schools::NeisFetcher.new(api_key: "K", connection: connection, max_attempts: 1).fetch_all
    end
  end
end
