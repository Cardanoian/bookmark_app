require "json"

module Schools
  # NEIS 학교기본정보 OpenAPI(open.neis.go.kr `schoolInfo`) 래퍼(계획 §1.2). 전국 초등학교를
  # 페이지네이션으로 수집해 정규화 행 배열로 반환한다. dev 전용 `schools:fetch` 가 소비하며,
  # 결과는 db/seeds/schools.csv 로 구워 오프라인 `schools:seed_full` 이 읽는다(시드=무네트워크).
  #
  # 키가 없으면 `available?` false → 빈 배열. 네트워크/파싱 실패는 FetchError 로 명확히
  # 실패시켜 호출자가 기존 전국 CSV를 보존하게 한다(부분 성공을 전량으로 오인하지 않음).
  # connection 은 테스트에서 스텁 Faraday 연결을 주입(네트워크 차단)한다 — SearchService 패턴.
  class NeisFetcher
    class FetchError < StandardError; end

    Page = Data.define(:rows, :total_count)

    BASE_URL = "https://open.neis.go.kr".freeze
    PATH = "/hub/schoolInfo".freeze
    PAGE_SIZE = 1000
    KIND = "초등학교".freeze
    DOMESTIC_OFFICE_CODES = Schools::SnapshotValidator::EXPECTED_OFFICE_CODES
    MAX_ATTEMPTS = 3
    RETRY_BASE_SECONDS = 0.25

    def self.available?
      new.available?
    end

    # 키 소스: ENV 가 있으면 우선, 없으면 credentials 폴백(운영자 대안 경로, docs/API_KEYS.md §5·§6).
    def initialize(api_key: ENV["NEIS_API_KEY"].presence || Rails.application.credentials.dig(:neis, :api_key),
      connection: nil, max_attempts: MAX_ATTEMPTS, sleeper: ->(seconds) { sleep(seconds) })
      @api_key = api_key.to_s
      @connection = connection
      @max_attempts = max_attempts
      @sleeper = sleeper
    end

    def available?
      @api_key.present?
    end

    # 전량 초등학교 정규화 행({neis_code:,name:,region:,gu:,office_code:,address:}) 배열.
    # 무키면 []. 실패/불완전 수집이면 FetchError. API head 의 전체 건수까지 모두 받은 경우에만
    # 정규화 결과를 반환하므로 마지막 페이지 장애로 앞 페이지만 CSV에 저장되는 일을 막는다.
    def fetch_all
      return [] unless available?

      raw_rows = []
      expected_total = nil
      page = 1
      loop do
        result = fetch_page(page)
        expected_total ||= result.total_count
        if result.total_count != expected_total
          raise FetchError, "NEIS 전체 건수가 페이지 사이에 변경되었습니다"
        end

        raw_rows.concat(result.rows)
        break if raw_rows.size >= expected_total

        if result.rows.empty?
          raise FetchError, "NEIS #{page}페이지가 전체 수집 전에 비어 있습니다"
        end

        page += 1
      end

      if raw_rows.size != expected_total
        raise FetchError, "NEIS 수집 건수가 일치하지 않습니다(#{raw_rows.size}/#{expected_total})"
      end

      normalize(raw_rows)
    end

    private

    # 한 페이지의 원본 row와 API head 전체 건수. 일시 장애는 지수 백오프로 재시도한다.
    def fetch_page(page)
      attempts = 0
      begin
        attempts += 1
        fetch_page_once(page)
      rescue Faraday::Error, JSON::ParserError, FetchError => error
        raise FetchError, "NEIS #{page}페이지 수집 실패: #{error.message}" if attempts >= @max_attempts

        @sleeper.call(RETRY_BASE_SECONDS * (2**(attempts - 1)))
        retry
      end
    end

    def fetch_page_once(page)
      response = connection.get(PATH) do |req|
        req.params["KEY"] = @api_key
        req.params["Type"] = "json"
        req.params["pIndex"] = page
        req.params["pSize"] = PAGE_SIZE
        req.params["SCHUL_KND_SC_NM"] = KIND
      end
      raise FetchError, "HTTP #{response.status}" unless response.success?

      body = response.body
      payload = body.is_a?(String) ? JSON.parse(body) : body
      sections = payload["schoolInfo"]
      raise FetchError, "schoolInfo 응답이 없습니다" unless sections.is_a?(Array)

      head = Array(sections.dig(0, "head"))
      result = head.filter_map { |item| item["RESULT"] }.first
      if result.present? && result["CODE"] != "INFO-000"
        raise FetchError, "#{result['CODE']}: #{result['MESSAGE']}"
      end

      total_count = head.filter_map { |item| item["list_total_count"] }.first
      raise FetchError, "전체 건수가 없습니다" unless total_count.to_s.match?(/\A\d+\z/)

      Page.new(rows: Array(sections.dig(1, "row")), total_count: total_count.to_i)
    end

    def normalize(raw_rows)
      raw_rows.filter_map do |row|
        # 서버 필터(SCHUL_KND_SC_NM)를 방어적으로 재확인 — 초등학교만 적재한다.
        next unless row["SCHUL_KND_SC_NM"].to_s.strip == KIND
        # 국내 17개 시도교육청만 적재하고 재외한국학교교육청(V10)은 제외한다.
        office_code = row["ATPT_OFCDC_SC_CODE"].to_s.strip
        next unless DOMESTIC_OFFICE_CODES.include?(office_code)

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
          office_code: office_code,
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
