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
    # 검색 버튼(원격) 결과 메타의 서버측 캐시 TTL. 검색~제출 사이 재사용 창(OCR 편집 등
    # 긴 세션 감안). 만료되면 register 가 `#query` 폴백으로 자동 degrade(튜너블).
    META_CACHE_TTL = 6.hours

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
        attach_ids(results)
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

    # 검색 버튼(원격) 전용(§Step2·Q3 캐시 방식). 네이버 결과를 표시용으로 반환하면서
    # 각 결과의 정규화 메타를 isbn 키로 짧게 캐시한다(제출 시 `#register` 가 재사용 →
    # 네이버 이중 왕복·제출 블로킹 제거). `books` 테이블엔 쓰지 않으므로(캐시만) 카탈로그
    # 오염·고아 행 0. 빈 isbn 결과는 캐시하지 않는다. 무키/실패 시 `#query` 가 [] 반환.
    def remote_search(term)
      results = query(term)
      results.each do |attrs|
        isbn = attrs[:isbn]
        Rails.cache.write("book_meta:#{isbn}", attrs, expires_in: META_CACHE_TTL) if isbn.present?
      end
      results
    end

    # 제출 시 도서 등록(캐시-우선 3단, raise 금지). 클라이언트가 보낸 title/author 는 절대
    # 저장하지 않고 서버/캐시가 네이버에서 도출한 메타만 저장한다(불변식 "학생 저작 Book 0").
    #   1) 이미 등록/카탈로그에 있으면(isbn 매칭) 그 Book 을 반환.
    #   2) 검색 시 적재한 캐시 히트면 upsert → Book 반환(네이버 재호출 없음 — 대부분 경로).
    #   3) 미스(TTL 만료 등)면 `#query(isbn)` 폴백 재조회 후, 요청 isbn 과 정확히 일치하는
    #      항목만 upsert. 없으면 nil.
    # 모든 실패(무키·네트워크·미일치·캐시 read 실패)는 예외 없이 nil 로 degrade 한다
    # (비차단 계약 — `@report.save` 밖 전처리에서 호출되며 save 를 막거나 롤백하지 않는다).
    def register(isbn)
      isbn = isbn.to_s.strip
      return nil if isbn.blank?

      existing = Book.find_by(isbn: isbn)
      return existing if existing

      meta = Rails.cache.read("book_meta:#{isbn}")
      return upsert(meta) if meta

      match = query(isbn).find { |attrs| attrs[:isbn] == isbn }
      match ? upsert(match) : nil
    rescue StandardError
      nil
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
          id: nil, # 로컬 Book PK. cache 후 attach_ids 가 isbn 으로 채운다(미매칭이면 nil 유지).
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
          id: book.id,
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
      results.each { |attrs| upsert(attrs) }
    end

    # 단건 네이버 결과를 books 에 isbn upsert 한다(category: :searched). 빈 isbn 은 건너뛰고
    # 저장된(또는 선존) Book 을 반환한다(`#register` 캐시-우선 경로가 재사용).
    #
    # 부분 유니크 인덱스(index_books_on_isbn) 도입 후, 동시 동일-isbn 신규 등록 레이스가
    # `save` 시점에 RecordNotUnique 를 낼 수 있다. 이를 rescue 해 선존 행을 재조회함으로써
    # 500 없이 단일 행으로 수렴시킨다(무키 기본 0 리스크, 키 환경 간헐·자가치유).
    def upsert(attrs)
      isbn = attrs[:isbn]
      return nil if isbn.blank?

      book = Book.find_or_initialize_by(isbn: isbn)
      is_new = book.new_record?
      book.title = attrs[:title] if attrs[:title].present?
      book.author = attrs[:author]
      book.publisher = attrs[:publisher]
      book.cover_url = attrs[:thumbnail]
      book.summary = attrs[:description]
      book.category = :searched if is_new
      saved = book.save

      # 신규로 캐시된 searched 도서(장르 미상)는 비동기 메타 보강(장르 등) 대상으로 예약한다.
      BookEnrichmentJob.perform_later(book.id) if saved && is_new && book.genre.blank?
      book
    rescue ActiveRecord::RecordNotUnique
      # 동시 동일-isbn 신규 등록 레이스 — 선존 행을 재조회해 단일 행으로 수렴.
      Book.find_by(isbn: isbn)
    end

    # 원격 결과에 로컬 Book PK 를 붙인다(cache upsert 후 isbn 매칭). 빈 isbn·미매칭은 nil.
    def attach_ids(results)
      results.each do |attrs|
        isbn = attrs[:isbn]
        attrs[:id] = isbn.present? ? Book.find_by(isbn: isbn)&.id : nil
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
