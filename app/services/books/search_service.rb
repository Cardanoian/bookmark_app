require "json"

module Books
  # 도서 검색(P5.1, RAILS_PLAN §9.6). 네이버 도서 검색 API 로 조회하고, 결과를 정규화해
  # `{ title, author, publisher, thumbnail, isbn, description }` 배열로 반환한다.
  #
  # 키가 비어 있거나(placeholder) 요청이 실패하면 로컬 캐시(`books` 테이블, title LIKE)로
  # graceful 폴백 — 네트워크 없이도 크래시하지 않는다.
  # 원격 결과는 `category: :searched` 로 `books` 에 isbn upsert 캐시한다.
  class SearchService
    NAVER_BASE = "https://openapi.naver.com".freeze
    NAVER_PATH = "/v1/search/book.json".freeze

    # connection 은 테스트에서 스텁 Faraday 연결을 주입(네트워크 차단)한다.
    # 키 소스: ENV 가 있으면 우선, 없으면 credentials 폴백(운영자 대안 경로, docs/API_KEYS.md §5·§6).
    def initialize(
      naver_id: ENV["NAVER_CLIENT_ID"].presence || Rails.application.credentials.dig(:naver, :client_id),
      naver_secret: ENV["NAVER_CLIENT_SECRET"].presence || Rails.application.credentials.dig(:naver, :client_secret),
      naver_connection: nil
    )
      @naver_id = naver_id.to_s
      @naver_secret = naver_secret.to_s
      @naver_connection = naver_connection
    end

    # 네이버 키가 모두 있으면 원격 검색 가능(네트워크 호출 없음).
    def self.available?
      new.available?
    end

    def available?
      naver_configured?
    end

    # 정규화된 결과 배열을 반환. 원격 성공 시 캐시, 실패/무키 시 로컬 폴백.
    def call(query)
      term = query.to_s.strip
      return [] if term.blank?

      results = fetch_from_naver(term)
      if results
        cache(results)
        results
      else
        local_matches(term)
      end
    end

    # 캐시 부작용 없는 조회(books:enrich 용). `call` 은 성공 시 결과를 `category: :searched`
    # 로 upsert 캐시하는데, 큐레이션 도서 메타보강은 큐레이션 행만 갱신해야 하므로(별도 searched
    # 행 오염 방지, 계획 §3.2) 캐시하지 않는 이 경로를 쓴다. 무키/실패 시 [](로컬 폴백도 없음).
    def query(term)
      term = term.to_s.strip
      return [] if term.blank?

      fetch_from_naver(term) || []
    end

    private

    def naver_configured?
      @naver_id.present? && @naver_secret.present?
    end

    # 성공 시 정규화 배열, 미설정/실패 시 nil(로컬 폴백).
    def fetch_from_naver(query)
      return nil unless naver_configured?

      response = naver_connection.get(NAVER_PATH) do |req|
        req.params["query"] = query
        req.headers["X-Naver-Client-Id"] = @naver_id
        req.headers["X-Naver-Client-Secret"] = @naver_secret
      end
      return nil unless response.success?

      normalize_naver(response.body)
    rescue Faraday::Error
      nil
    end

    def normalize_naver(body)
      Array(parse(body)["items"]).filter_map do |item|
        next unless item.is_a?(Hash)

        title = item["title"].to_s
        next if title.blank?

        {
          title: title,
          author: item["author"].to_s.tr("^", ",").squeeze(",").gsub(",", ", ").strip,
          publisher: item["publisher"].to_s,
          thumbnail: item["image"].to_s,
          isbn: pick_isbn(item["isbn"]),
          description: item["description"].to_s
        }
      end
    end

    # 로컬 캐시 폴백: 제목 부분 일치. 정규화 형식으로 반환.
    def local_matches(query)
      pattern = "%#{Book.sanitize_sql_like(query)}%"
      Book.where("title LIKE ?", pattern).order(:title).limit(20).map do |book|
        {
          title: book.title.to_s,
          author: book.author.to_s,
          publisher: book.publisher.to_s,
          thumbnail: book.cover_url.to_s,
          isbn: book.isbn.to_s,
          description: book.summary.to_s
        }
      end
    end

    # 원격 결과를 books 에 isbn upsert 캐시(category: :searched). 빈 isbn 은 건너뛴다.
    #
    # 무한 증가 방어(#2): searched 행은 카탈로그 index 에서 제외되어(BooksController)
    # 목록 UX 를 오염시키지 않는다. 테이블 자체의 TTL/정리는, searched 도서가 학생
    # 독후감(reports.book_id, on_delete: nullify)에 참조될 수 있어 무조건 삭제하면
    # 참조가 끊기므로, 미참조 오래된 행만 주기적으로 비우는 별도 정리 태스크로 다룬다
    # (카탈로그 제외가 1차 방어, 물리 정리는 후속). isbn upsert 자체가 중복 행을 막는다.
    def cache(results)
      results.each do |attrs|
        isbn = attrs[:isbn]
        next if isbn.blank?

        book = Book.find_or_initialize_by(isbn: isbn)
        book.title = attrs[:title] if attrs[:title].present?
        book.author = attrs[:author]
        book.publisher = attrs[:publisher]
        book.cover_url = attrs[:thumbnail]
        book.summary = attrs[:description]
        book.category = :searched if book.new_record?
        book.save
      end
    end

    # 네이버는 "ISBN10 ISBN13" 처럼 공백 구분 문자열을 주기도 한다. 긴 쪽(ISBN13) 우선.
    def pick_isbn(raw)
      raw.to_s.split.max_by(&:length).to_s
    end

    def parse(body)
      body.is_a?(String) ? JSON.parse(body) : body
    rescue JSON::ParserError
      {}
    end

    def naver_connection
      @naver_connection ||= Faraday.new(url: NAVER_BASE, request: { open_timeout: 3, timeout: 8 }) do |faraday|
        faraday.adapter Faraday.default_adapter
      end
    end
  end
end
