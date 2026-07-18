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

      assign(book, match)
      # 부분 유니크 인덱스(index_books_on_isbn) 하에선 같은 isbn 공존이 불가하므로, 큐레이션
      # 행에 부여할 isbn 과 겹치는 선존 searched 캐시 행을 save! **이전**에 정리한다(정본=큐레이션
      # 행). save 후 정리하면 저장 시점에 RecordNotUnique 가 난다.
      reconcile_searched_duplicate!(book)
      book.save!
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

    # 매치 메타를 큐레이션 도서에 대입만 한다(저장은 enrich_one 이 reconcile 뒤에 수행).
    def assign(book, match)
      book.isbn = match[:isbn] if match[:isbn].present?
      book.cover_url = match[:thumbnail] if match[:thumbnail].present?
      book.publisher = match[:publisher] if match[:publisher].present?
      book.author = match[:author] if match[:author].present? && book.author.blank?
    end

    # 큐레이션 행에 isbn 을 부여했을 때 같은 isbn 의 선존 :searched 캐시 행(학생 검색이 미리
    # 만든 것)을 정리한다 — 큐레이션 행이 정본. 단 그 :searched 행을 참조하던 독후감 링크는
    # 삭제 전에 정본(큐레이션) 도서로 **이관**해 보존한다(reports.book_id 는 on_delete: nullify 라
    # 곧바로 delete 하면 링크가 끊긴다 → books:seed_full 의 제자리 승격과 동일한 링크 보존 정책·§8).
    def reconcile_searched_duplicate!(book)
      return if book.isbn.blank?

      dupe_ids = Book.searched.where(isbn: book.isbn).where.not(id: book.id).ids
      return if dupe_ids.empty?

      Report.where(book_id: dupe_ids).update_all(book_id: book.id)
      Book.where(id: dupe_ids).delete_all
    end
  end
end
