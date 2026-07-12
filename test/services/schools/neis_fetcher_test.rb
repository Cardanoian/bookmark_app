require "test_helper"

# NEIS 학교기본정보 페처 단위 테스트(계획 §1.2). 스텁 Faraday 연결로 네트워크를 차단하고
# 초등학교만 필터·필드 매핑·gu 파싱·페이지네이션·무키 폴백을 검증한다(SearchService DI 패턴).
class Schools::NeisFetcherTest < ActiveSupport::TestCase
  def stub_connection(&block)
    stubs = Faraday::Adapter::Test::Stubs.new(&block)
    Faraday.new { |faraday| faraday.adapter :test, stubs }
  end

  def neis_body(rows)
    { "schoolInfo" => [ { "head" => [] }, { "row" => rows } ] }.to_json
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

  test "maps NEIS fields, parses gu, and keeps only 초등학교" do
    connection = stub_connection do |stub|
      stub.get("/hub/schoolInfo") do
        [ 200, {}, neis_body([
          neis_row(code: "S1", name: "서울강남초", region: "서울특별시교육청", office: "B10", addr: "서울특별시 강남구 언주로 3"),
          neis_row(code: "M1", name: "중학교아님", kind: "중학교"),
          neis_row(code: "", name: "코드없음"),
          neis_row(code: "N1", name: "")
        ]) ]
      end
    end
    fetcher = Schools::NeisFetcher.new(api_key: "K", connection: connection)

    rows = fetcher.fetch_all

    assert_equal 1, rows.size, "초등학교·유효 코드/이름만 남아야 한다"
    row = rows.first
    assert_equal "S1", row[:neis_code]
    assert_equal "서울강남초", row[:name]
    assert_equal "서울특별시교육청", row[:region]
    assert_equal "강남구", row[:gu]
    assert_equal "B10", row[:office_code]
    assert_equal "서울특별시 강남구 언주로 3", row[:address]
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

  test "paginates until a batch smaller than the page size" do
    page1 = Array.new(Schools::NeisFetcher::PAGE_SIZE) { |i| neis_row(code: "P1#{i}", name: "초등#{i}") }
    page2 = [ neis_row(code: "P2", name: "막초등") ]
    connection = stub_connection do |stub|
      stub.get("/hub/schoolInfo") do |env|
        rows = env.params["pIndex"].to_i == 1 ? page1 : page2
        [ 200, {}, neis_body(rows) ]
      end
    end
    fetcher = Schools::NeisFetcher.new(api_key: "K", connection: connection)

    result = fetcher.fetch_all

    assert_equal Schools::NeisFetcher::PAGE_SIZE + 1, result.size
    assert_equal "P2", result.last[:neis_code]
  end

  test "returns [] without crashing on a server error" do
    connection = stub_connection { |stub| stub.get("/hub/schoolInfo") { [ 500, {}, "error" ] } }
    fetcher = Schools::NeisFetcher.new(api_key: "K", connection: connection)

    assert_equal [], fetcher.fetch_all
  end
end
