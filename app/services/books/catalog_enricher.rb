module Books
  # 큐레이션 카탈로그 도서의 표지·출판사를 ISBN 기반 네이버 검색으로 보강한다(계획 §3.2).
  # books:enrich(수동·네트워크) 가 소비. SearchService#query(캐시 부작용 없는 조회)만 써서
  # 큐레이션 행만 제자리 갱신하고, 별도 :searched 행을 만들지 않는다.
  #
  # 네이버가 색인하지 못한 절판·구판본(ISBN 0건)은 정보나루(data4library) 도서 상세조회의
  # 표지로 폴백해 표지만 채운다(출판사·저자는 큐레이션 XLSX 값을 보존). 두 공급원 모두
  # 무키/실패면 no-op(0건).
  #
  # service·library·throttle 을 주입 가능하게 해 오프라인 단위 테스트를 지원한다(DI 패턴).
  class CatalogEnricher
    def initialize(service: Books::SearchService.new, library: Library::Data4libraryService.new, throttle: 0.15)
      @service = service
      @library = library
      @throttle = throttle
    end

    # cover 결측 큐레이션(recommended·classic) 도서를 보강. 갱신 건수 반환.
    def enrich_all
      enrich(pending)
    end

    # 지정 scope 의 도서를 순차 보강한다. 추천도서 업로드 잡이 해당 import 에
    # 속한 책만 처리할 때 재사용한다. 한 잡 안에서 throttle 해 API 동시 호출 폭증을 막는다.
    def enrich(scope)
      return 0 unless enrichable?

      updated = 0
      scope.find_each do |book|
        updated += 1 if enrich_one(book)
        # 매치 실패도 API 요청량에는 포함되므로 모든 시도 사이를 늦춘다.
        sleep @throttle if @throttle.to_f.positive? # 아웃바운드 스로틀(순차 보험)
      end
      updated
    end

    # 한 권을 ISBN으로 보강. 네이버 ISBN 정확 일치를 우선 적용하고, 없으면 정보나루 표지로
    # 폴백한다. 어느 공급원도 채우지 못하면 false(변경 없음).
    def enrich_one(book)
      match = pick_match(@service.query(book.isbn), book)
      if match
        assign(book, match)
        book.save!
        return true
      end

      cover = fallback_cover(book)
      return false if cover.blank?

      book.cover_url = cover
      book.save!
      true
    end

    private

    # 네이버·정보나루 중 하나라도 사용 가능하면 보강을 시도한다(무키 양쪽이면 no-op).
    def enrichable?
      @service.available? || @library.available?
    end

    # 네이버 미색인(ISBN 0건) 시 정보나루 도서 상세조회의 표지로 폴백. 무키/미존재면 nil.
    def fallback_cover(book)
      return nil unless @library.available?

      @library.cover_url_for(Books::Isbn.normalize(book.isbn))
    end

    # cover_url 이 빈 큐레이션 도서(searched 제외).
    def pending
      Book.where(category: [ Book.categories[:recommended], Book.categories[:classic] ])
          .where("cover_url IS NULL OR cover_url = ''")
    end

    # 정확히 같은 ISBN 결과만 허용한다. 불일치 시 다른 판본의 표지를 붙이지 않고 건너뛴다.
    def pick_match(results, book)
      return nil if results.blank?

      isbn = Books::Isbn.normalize(book.isbn)
      results.find { |result| Books::Isbn.normalize(result[:isbn]) == isbn }
    end

    # 매치 메타를 큐레이션 도서에 대입만 한다(저장은 enrich_one 이 수행).
    def assign(book, match)
      book.cover_url = match[:thumbnail] if match[:thumbnail].present?
      book.publisher = match[:publisher] if match[:publisher].present?
      book.author = match[:author] if match[:author].present? && book.author.blank?
    end
  end
end
