require "json"

module Library
  # 정보나루(data4library.kr) 인기대출 OpenAPI 래퍼(P6.5, RAILS_PLAN §9.7).
  #
  # 키가 없으면 `available?` 이 false → 호출자는 CSV 업로드 폴백 안내를 보인다.
  # 키가 있어도 네트워크·파싱 실패 시 빈 배열을 반환하고 절대 크래시하지 않는다.
  # 반환 형식: `[{ book_title:, isbn:, count: }, ...]`.
  class Data4libraryService
    BASE_URL = "http://data4library.kr".freeze
    PATH = "/api/loanItemSrch".freeze

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
    def popular_loans(from: nil, to: nil, page_size: 10)
      return [] unless available?

      response = connection.get(PATH) do |req|
        req.params["authKey"] = @api_key
        req.params["format"] = "json"
        req.params["pageSize"] = page_size
        req.params["startDt"] = from if from.present?
        req.params["endDt"] = to if to.present?
      end
      return [] unless response.success?

      normalize(response.body)
    rescue Faraday::Error
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
      []
    end

    def connection
      @connection ||= Faraday.new(url: BASE_URL) do |faraday|
        faraday.adapter Faraday.default_adapter
      end
    end
  end
end
