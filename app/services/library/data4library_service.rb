require "json"

module Library
  # 정보나루(data4library.kr) 인기대출 OpenAPI 래퍼(P6.5, RAILS_PLAN §9.7).
  #
  # 키가 없으면 `available?` 이 false → 호출자는 CSV 업로드 폴백 안내를 보인다.
  # 키가 있어도 네트워크·파싱 실패 시 빈 배열을 반환하고 절대 크래시하지 않는다.
  # 실패 사유는 `last_error` 로 노출해 호출자가 "0건 성공" 과 "동기화 실패" 를 구분한다.
  # 반환 형식: `[{ book_title:, isbn:, count: }, ...]`.
  class Data4libraryService
    BASE_URL = "http://data4library.kr".freeze
    PATH = "/api/loanItemSrch".freeze

    # 직전 popular_loans 호출의 실패 사유. 성공·무키 시 nil.
    attr_reader :last_error

    # 키 존재 여부만으로 사용 가능 판단(네트워크 호출 없음).
    def self.available?
      new.available?
    end

    # connection: 테스트에서 스텁 Faraday 연결을 주입(네트워크 차단).
    def initialize(api_key: Rails.application.credentials.dig(:data4library, :api_key), connection: nil)
      @api_key = api_key.to_s
      @connection = connection
    end

    def available?
      @api_key.present?
    end

    # 인기대출 목록을 정규화 배열로 반환. 무키·실패 시 [] (호출자가 CSV 폴백).
    # from/to: 대출 집계 기간("YYYY-MM-DD" 또는 Date). 생략 시 API 기본 기간.
    def popular_loans(from: nil, to: nil, page_size: 10)
      @last_error = nil
      return [] unless available?

      response = connection.get(PATH) do |req|
        req.params["authKey"] = @api_key
        req.params["format"] = "json"
        req.params["pageSize"] = page_size
        req.params["startDt"] = from if from.present?
        req.params["endDt"] = to if to.present?
      end
      unless response.success?
        @last_error = "정보나루 응답 오류 (HTTP #{response.status})"
        return []
      end

      normalize(response.body)
    rescue Faraday::Error => e
      @last_error = "정보나루 연결 실패 (#{e.class})"
      []
    end

    private

    def normalize(body)
      payload = body.is_a?(String) ? JSON.parse(body) : body
      docs = payload.dig("response", "docs") || []
      docs.filter_map do |entry|
        doc = entry.is_a?(Hash) ? (entry["doc"] || entry) : {}
        title = doc["bookname"].to_s.strip
        next if title.blank?

        { book_title: title, isbn: doc["isbn13"].to_s.strip, count: doc["loan_count"].to_i }
      end
    rescue JSON::ParserError
      @last_error = "정보나루 응답 파싱 실패"
      []
    end

    def connection
      @connection ||= Faraday.new(url: BASE_URL) do |faraday|
        faraday.adapter Faraday.default_adapter
      end
    end
  end
end
