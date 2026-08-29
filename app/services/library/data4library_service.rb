require "json"

module Library
  # 정보나루(data4library.kr) 인기대출 OpenAPI 래퍼(P6.5, RAILS_PLAN §9.7).
  #
  # 키가 없으면 `available?` 이 false → 호출자는 CSV 업로드 폴백 안내를 보인다.
  # 키가 있어도 네트워크·파싱 실패 시 빈 배열을 반환하고 절대 크래시하지 않는다.
  # 실패 사유는 `last_error` 로 노출해 호출자가 "0건 성공" 과 "동기화 실패" 를 구분한다.
  # 반환 형식: `[{ book_title:, isbn:, count: }, ...]`.
  class Data4libraryService
    BASE_URL = "https://data4library.kr".freeze
    PATH = "/api/loanItemSrch".freeze
    # 도서 상세조회(표지 URL 공급). 네이버가 색인하지 못한 절판·구판본의 표지를 여기서 얻는다.
    DETAIL_PATH = "/api/srchDtlList".freeze
    # 이 책을 소장한 도서관 목록(인근 도서관 §5.2). region=정보나루 시도 코드로 조회.
    LIB_SEARCH_PATH = "/api/libSrchByBook".freeze
    # 도서관별 소장·대출 가능 여부(불리언, 권수 없음).
    BOOK_EXIST_PATH = "/api/bookExist".freeze
    # ⚠️ 아래 두 상한은 **운영 실측에 맞춘 값이다**(2026-08-29, 운영 컨테이너에서 직접 측정).
    #   추측으로 조이면 조용히 전부 실패한다 — 실제로 한 번 그랬다(6초로 잡았다가 9.5초짜리
    #   호출이 매번 잘려 도서관 섹션이 통째로 사라질 뻔했다).
    #
    #   · libSrchByBook : **9.2~9.8초** (pageSize 100 이든 1000 이든 같다 — 응답 크기가 아니라
    #                      서버 지연이다. 줄여도 안 빨라진다.)
    #   · bookExist     : **7.9~35.5초** (편차 4배. 5곳 순차 합 101초, 동시 8.7초.)
    #
    #   둘 다 이제 **렌더 밖(NearbyLibrariesWarmJob)에서만** 불리므로 요청을 막지 않는다.
    #   그래서 실측 위에 여유를 얹어 잡는다 — 여기서 조이면 캐시가 영영 안 채워진다.
    BOOK_EXIST_READ_TIMEOUT = 20
    LIB_SEARCH_READ_TIMEOUT = 20

    # 직전 popular_loans 호출의 실패 사유. 성공·무키 시 nil.
    attr_reader :last_error

    # 키 존재 여부만으로 사용 가능 판단(네트워크 호출 없음).
    def self.available?
      new.available?
    end

    # connection: 테스트에서 스텁 Faraday 연결을 주입(네트워크 차단).
    # 키 소스: ENV 가 있으면 우선, 없으면 credentials 폴백(운영자 대안 경로, docs/API_KEYS.md §5·§6).
    def initialize(api_key: ENV["DATA4LIBRARY_KEY"].presence || Rails.application.credentials.dig(:data4library, :api_key), connection: nil)
      @api_key = api_key.to_s
      @connection = connection
    end

    def available?
      @api_key.present?
    end

    # 인기대출 목록을 정규화 배열로 반환. 무키·실패 시 [] (호출자가 CSV 폴백).
    # from/to: 대출 집계 기간("YYYY-MM-DD" 또는 Date). 생략 시 API 기본 기간.
    # age: 연령대 코드(예 "a8"·"a10"·"a12", 발견 학년군 인기도서). 있을 때만 전송(하위호환).
    def popular_loans(from: nil, to: nil, page_size: 10, age: nil)
      @last_error = nil
      return [] unless available?

      response = connection.get(PATH) do |req|
        # 정보나루 API 는 헤더 인증을 지원하지 않고 authKey 쿼리 파라미터만 문서화되어 있다.
        # BASE_URL 이 https 이므로 쿼리 문자열은 TLS 로 보호된다(과거 http 로 노출된 키는 회전할 것).
        req.params["authKey"] = @api_key
        req.params["format"] = "json"
        req.params["pageSize"] = page_size
        req.params["startDt"] = from if from.present?
        req.params["endDt"] = to if to.present?
        req.params["age"] = age if age.present?
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

    # ISBN-13 도서 상세조회로 표지 이미지 URL 을 반환한다(네이버 미색인 판본의 표지 폴백,
    # Books::CatalogEnricher 가 소비). loaninfoYN=N 으로 대출정보 조회를 생략해 가볍게 요청한다.
    # 무키·네트워크·파싱 실패·표지 없음(빈 문자열)·미존재 시 nil → 호출자는 표지 미보강으로
    # 우아하게 degrade 한다. popular_loans 의 last_error 계약을 오염시키지 않도록 여기서는
    # last_error 를 건드리지 않는다(두 메서드는 독립).
    def cover_url_for(isbn13)
      isbn = isbn13.to_s.strip
      return nil if isbn.blank? || !available?

      response = connection.get(DETAIL_PATH) do |req|
        req.params["authKey"] = @api_key
        req.params["format"] = "json"
        req.params["isbn13"] = isbn
        req.params["loaninfoYN"] = "N" # 대출정보 조회 생략(표지만 필요)
      end
      return nil unless response.success?

      extract_cover(response.body)
    rescue Faraday::Error
      nil
    end

    # 시도(region) 안에서 이 책을 소장한 도서관 목록을 정규화 배열로 반환(인근 도서관 §5.2).
    # 응답 구조는 response.libs[].lib (인기대출의 docs[].doc 와 다름 — 파서 재사용 주의).
    # 반환: [{ code:, name:, address:, tel:, homepage:, latitude:, longitude: }, ...].
    # 무키·미존재(빈 결과) → [] / 원격 실패(비200·연결) → nil(호출자가 :none 과 :error 를 구분).
    # cover_url_for 처럼 popular_loans 전용 last_error 는 오염시키지 않는다(메서드 독립).
    def libraries_holding(isbn13:, region:, page_size: 1000, timeout: LIB_SEARCH_READ_TIMEOUT)
      isbn = isbn13.to_s.strip
      code = region.to_s.strip
      return [] if isbn.blank? || code.blank? || !available?

      response = connection.get(LIB_SEARCH_PATH) do |req|
        req.options.timeout = timeout
        req.params["authKey"] = @api_key
        req.params["format"] = "json"
        req.params["isbn"] = isbn
        req.params["region"] = code
        req.params["pageSize"] = page_size
      end
      return nil unless response.success?

      normalize_libraries(response.body, page_size: page_size)
    rescue Faraday::Error
      nil
    end

    # 한 도서관에서 이 책의 대출 가능 여부(인근 도서관 §5.2). loanAvailable Y→:available /
    # N→:unavailable / (에러·미존재)→:unknown. fetched_at 을 값에 동봉해 캐시 히트 시에도
    # "언제 조회한 값인지"가 보존되게 한다(정직 라벨 근거). 무키·실패 시에도 크래시 없이 :unknown.
    # timeout: 호출자가 **남은 시간예산**을 넘겨 상한을 더 좁힐 수 있다(NearbyAvailability 가
    # 팬아웃 전체를 예산 안에 가두는 데 쓴다). 미지정이면 기존 4s 그대로.
    def loan_status(lib_code:, isbn13:, timeout: BOOK_EXIST_READ_TIMEOUT)
      code = lib_code.to_s.strip
      isbn = isbn13.to_s.strip
      return unknown_status if code.blank? || isbn.blank? || !available?

      response = connection.get(BOOK_EXIST_PATH) do |req|
        req.options.timeout = timeout
        req.params["authKey"] = @api_key
        req.params["format"] = "json"
        req.params["libCode"] = code
        req.params["isbn13"] = isbn
      end
      return unknown_status unless response.success?

      { status: extract_loan_status(response.body), fetched_at: Time.current }
    rescue Faraday::Error
      unknown_status
    end

    private

    def unknown_status
      { status: :unknown, fetched_at: Time.current }
    end

    # libSrchByBook 응답(response.libs[].lib)을 정규화한다. numFound 가 page_size 를 넘으면
    # 잘린 목록이므로 경고만 남긴다(재페이지네이션은 후속 — 현실적으로 시도당 1페이지).
    def normalize_libraries(body, page_size:)
      payload = body.is_a?(String) ? JSON.parse(body) : body
      response = payload["response"] || {}
      num_found = response["numFound"].to_i
      if num_found > page_size
        Rails.logger.warn("[data4library] libSrchByBook truncated: numFound=#{num_found} > pageSize=#{page_size}")
      end

      libs = response["libs"] || []
      libs.filter_map do |entry|
        lib = entry.is_a?(Hash) ? (entry["lib"] || entry) : {}
        code = lib["libCode"].to_s.strip
        name = lib["libName"].to_s.strip
        next if code.blank? || name.blank?

        {
          code: code, name: name, address: lib["address"].to_s.strip,
          tel: lib["tel"].to_s.strip, homepage: lib["homepage"].to_s.strip,
          latitude: lib["latitude"].to_s.strip, longitude: lib["longitude"].to_s.strip
        }
      end
    rescue JSON::ParserError
      nil
    end

    # bookExist 응답(response.result.loanAvailable)에서 대출 가능 여부를 뽑는다.
    def extract_loan_status(body)
      payload = body.is_a?(String) ? JSON.parse(body) : body
      result = payload.dig("response", "result") || {}
      case result["loanAvailable"].to_s.strip.upcase
      when "Y" then :available
      when "N" then :unavailable
      else :unknown
      end
    rescue JSON::ParserError
      :unknown
    end

    def normalize(body)
      payload = body.is_a?(String) ? JSON.parse(body) : body
      docs = payload.dig("response", "docs") || []
      docs.filter_map do |entry|
        doc = entry.is_a?(Hash) ? (entry["doc"] || entry) : {}
        title = doc["bookname"].to_s.strip
        isbn = doc["isbn13"].to_s.strip
        next if title.blank? || isbn.blank?

        { book_title: title, isbn: isbn, count: doc["loan_count"].to_i }
      end
    rescue JSON::ParserError
      @last_error = "정보나루 응답 파싱 실패"
      []
    end

    # srchDtlList 응답에서 표지 URL 을 뽑는다. 구조: response.detail[0].book.bookImageURL.
    # 표지가 없는 도서는 빈 문자열을 주므로 presence 로 nil 정규화한다.
    def extract_cover(body)
      payload = body.is_a?(String) ? JSON.parse(body) : body
      detail = payload.dig("response", "detail")
      entry = detail.is_a?(Array) ? detail.first : detail
      book = entry.is_a?(Hash) ? (entry["book"] || entry) : nil
      return nil unless book.is_a?(Hash)

      book["bookImageURL"].to_s.strip.presence
    rescue JSON::ParserError
      nil
    end

    def connection
      @connection ||= Faraday.new(url: BASE_URL, request: { open_timeout: 3, timeout: 8 }) do |faraday|
        faraday.adapter Faraday.default_adapter
      end
    end
  end
end
