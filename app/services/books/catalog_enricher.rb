module Books
  # 큐레이션 카탈로그 도서의 표지·ISBN·출판사를 네이버 검색으로 보강한다(계획 §3.2).
  # books:enrich(수동·네트워크) 가 소비. SearchService#query(캐시 부작용 없는 조회)만 써서
  # 큐레이션 행만 제자리 갱신하고, 별도 :searched 행을 만들지 않는다. 무키/실패 시 no-op(0건).
  #
  # service·throttle 을 주입 가능하게 해 오프라인 단위 테스트를 지원한다(SearchService DI 패턴).
  class CatalogEnricher
    def initialize(service: Books::SearchService.new, throttle: 0.15)
      @service = service
      @throttle = throttle
    end

    # isbn/cover 결측 큐레이션(recommended·classic) 도서를 보강. 갱신 건수 반환.
    def enrich_all
      return 0 unless @service.available?

      updated = 0
      pending.find_each do |book|
        next unless enrich_one(book)

        updated += 1
        sleep @throttle if @throttle.to_f.positive? # 네이버 아웃바운드 스로틀(순차 보험)
      end
      updated
    end

    # 한 권을 보강. 매치가 없으면 false(변경 없음).
    def enrich_one(book)
      match = pick_match(@service.query(book.title), book.title)
      return false if match.nil?

      apply(book, match)
      reconcile_searched_duplicate!(book)
      true
    end

    private

    # isbn 또는 cover_url 이 빈 큐레이션 도서(searched 제외).
    def pending
      Book.where(category: [ Book.categories[:recommended], Book.categories[:classic] ])
          .where("isbn IS NULL OR isbn = '' OR cover_url IS NULL OR cover_url = ''")
    end

    # 제목 정규화 후 정확 일치 우선, 없으면 첫 결과.
    def pick_match(results, title)
      return nil if results.blank?

      normalized = normalize_title(title)
      results.find { |result| normalize_title(result[:title]) == normalized } || results.first
    end

    def normalize_title(title)
      title.to_s.gsub(/<[^>]+>/, "").gsub(/\s+/, "").strip
    end

    def apply(book, match)
      book.isbn = match[:isbn] if match[:isbn].present?
      book.cover_url = match[:thumbnail] if match[:thumbnail].present?
      book.publisher = match[:publisher] if match[:publisher].present?
      book.author = match[:author] if match[:author].present? && book.author.blank?
      book.save!
    end

    # 큐레이션 행에 isbn 을 부여했을 때 같은 isbn 의 선존 :searched 캐시 행(학생 검색이 미리
    # 만든 것)을 제거한다 — 큐레이션 행이 정본이므로 중복을 정리(계획 §3.2 Minor 2).
    def reconcile_searched_duplicate!(book)
      return if book.isbn.blank?

      Book.searched.where(isbn: book.isbn).where.not(id: book.id).delete_all
    end
  end
end
