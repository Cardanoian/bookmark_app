require "json"

module Schools
  # NEIS 학교기본정보 OpenAPI(open.neis.go.kr `schoolInfo`) 래퍼(계획 §1.2). 전국 초등학교를
  # 페이지네이션으로 수집해 정규화 행 배열로 반환한다. dev 전용 `schools:fetch` 가 소비하며,
  # 결과는 db/seeds/schools.csv 로 구워 오프라인 `schools:seed_full` 이 읽는다(시드=무네트워크).
  #
  # 키가 없으면 `available?` false → 빈 배열. 네트워크/파싱 실패도 크래시하지 않고 [] 반환.
  # connection 은 테스트에서 스텁 Faraday 연결을 주입(네트워크 차단)한다 — SearchService 패턴.
  class NeisFetcher
    BASE_URL = "https://open.neis.go.kr".freeze
    PATH = "/hub/schoolInfo".freeze
    PAGE_SIZE = 1000
    KIND = "초등학교".freeze

    def self.available?
      new.available?
    end

    # 키 소스: ENV 가 있으면 우선, 없으면 credentials 폴백(운영자 대안 경로, docs/API_KEYS.md §5·§6).
    def initialize(api_key: ENV["NEIS_API_KEY"].presence || Rails.application.credentials.dig(:neis, :api_key), connection: nil)
      @api_key = api_key.to_s
      @connection = connection
    end

    def available?
      @api_key.present?
    end

    # 전량 초등학교 정규화 행({neis_code:,name:,region:,gu:,office_code:,address:}) 배열.
    # 무키·실패 시 []. batch 가 PAGE_SIZE 미만이면 마지막 페이지로 보고 종료.
    def fetch_all
      return [] unless available?

      rows = []
      page = 1
      loop do
        raw = fetch_page(page)
        break if raw.empty?

        rows.concat(normalize(raw))
        # 종료 판정은 **원본** 행 수 기준(필터 후가 아님) — 만재 페이지가 필터로 일부를 잃어도
        # 조기 종료해 후속 페이지를 누락하지 않는다.
        break if raw.size < PAGE_SIZE

        page += 1
      end
      rows
    end

    private

    # 한 페이지의 원본 row 배열(정규화 전). 실패/파싱오류 시 [].
    def fetch_page(page)
      response = connection.get(PATH) do |req|
        req.params["KEY"] = @api_key
        req.params["Type"] = "json"
        req.params["pIndex"] = page
        req.params["pSize"] = PAGE_SIZE
        req.params["SCHUL_KND_SC_NM"] = KIND
      end
      return [] unless response.success?

      body = response.body
      payload = body.is_a?(String) ? JSON.parse(body) : body
      Array(payload.dig("schoolInfo", 1, "row"))
    rescue Faraday::Error, JSON::ParserError
      []
    end

    def normalize(raw_rows)
      raw_rows.filter_map do |row|
        # 서버 필터(SCHUL_KND_SC_NM)를 방어적으로 재확인 — 초등학교만 적재한다.
        next unless row["SCHUL_KND_SC_NM"].to_s.strip == KIND

        code = row["SD_SCHUL_CODE"].to_s.strip
        name = row["SCHUL_NM"].to_s.strip
        next if code.blank? || name.blank?

        address = row["ORG_RDNMA"].to_s.strip
        region = row["ATPT_OFCDC_SC_NM"].to_s.strip
        {
          neis_code: code,
          name: name,
          region: region,
          gu: Schools::GuParser.parse(address, region: region),
          office_code: row["ATPT_OFCDC_SC_CODE"].to_s.strip,
          address: address.presence
        }
      end
    end

    def connection
      @connection ||= Faraday.new(url: BASE_URL, request: { open_timeout: 5, timeout: 30 }) do |faraday|
        faraday.adapter Faraday.default_adapter
      end
    end
  end
end
