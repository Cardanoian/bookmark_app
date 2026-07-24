module Library
  # "이 책은 어때요?" 발견 섹션의 정보나루 학년군 인기도서 풀 캐시(무쓰기 카탈로그 매칭).
  # 정보나루(loanItemSrch) 인기대출 ISBN 을 기존 카탈로그(recommended/classic)와 교집합해
  # 매칭 book_id 를 학년군 단위로 인기순 캐시하고, StudentHomeQuery 가 그 풀에서 복원추출
  # 랜덤으로 6권을 노출한다. books 테이블 쓰기·category 변경·enrichment 팬아웃은 전무하다.
  #
  # 무키·실패·매칭 빈약 어떤 경우도 페이지를 깨지 않고 [] 로 degrade 한다(호출자가 기존 DB
  # discovery 회전으로 폴백). 렌더 경로(root#show)에서는 외부 HTTP 를 하지 않고 워밍 잡에
  # 위임하며, 반(班) 동시접속 콜드캐시도 원자 마커(unless_exist)로 밴드당 1콜/WARMING_TTL 로
  # 상한한다. cache·service·clock 을 주입 가능하게 해 결정적 캐시/기간 테스트를 지원한다
  # (NearbyAvailability 선례).
  class PopularDiscovery
    # 정보나루 인기대출 조회 상한(pageSize). 이 중 카탈로그와 매칭되는 것만 풀에 남는다.
    POOL_LIMIT = 200
    # 매칭이 이 미만이면 미캐시(폴백 유지) — 2페이지분이라 "다른 책 보기"가 유의미해진다.
    MIN_POOL = 12
    POOL_TTL = 7.days
    # 워밍 스탬피드 가드 마커 TTL. 진행 중이면 재큐잉을 스킵하고, 실패해도 자연만료로 재시도.
    WARMING_TTL = 5.minutes

    def initialize(cache: Rails.cache, service: Library::Data4libraryService.new, now: -> { Time.current })
      @cache = cache
      @service = service
      @now = now
    end

    # 학년군 풀(인기순 book_id 배열)을 반환한다. 캐시 히트면 그대로, 미스면 워밍 잡을 큐잉하고
    # 이번 렌더는 [](폴백)로 즉시 반환한다. 무키면 큐잉조차 하지 않는다(무키 배포에서 무한
    # enqueue 방지 — 워밍 잡도 무키면 no-op 이라 채워질 일이 없다).
    def pool_book_ids(band)
      cached = @cache.read(pool_key(band))
      return cached if cached

      return [] unless @service.available?

      acquired = @cache.write(warming_key(band), true, expires_in: WARMING_TTL, unless_exist: true)
      Library::PopularDiscoveryWarmJob.perform_later(band.to_s) if acquired
      []
    end

    # 학년군 인기도서 풀을 채운다(워밍 잡이 호출). 이미 풀이 있으면 no-op(멱등). 무키·매칭
    # 임계 미만이면 미캐시로 남겨 다음 접근에서 재시도한다.
    def warm(band)
      band = band.to_sym
      age = ReadingDomain::AGE_CODE_BY_BAND[band]
      return if age.blank?
      return if @cache.read(pool_key(band))

      month = @now.call.to_date.prev_month
      loans = @service.popular_loans(
        from: month.beginning_of_month.strftime("%Y-%m-%d"),
        to: month.end_of_month.strftime("%Y-%m-%d"),
        page_size: POOL_LIMIT,
        age: age
      )

      # ISBN 을 저장 경계와 같은 방식으로 정규화해 매칭 누락을 막는다(무효는 드롭, 순서 보존).
      normalized = loans.filter_map { |loan| Books::Isbn.normalize(loan[:isbn]) }

      # 카탈로그(non-searched)와의 교집합만 인기순으로 남긴다 — 발견 카드는 non-searched
      # Book.id 를 요구하므로(resolve_book) searched 는 배제한다.
      by_isbn = Book.where(isbn: normalized)
                    .where(category: [ Book.categories[:recommended], Book.categories[:classic] ])
                    .index_by(&:isbn)
      ordered_ids = normalized.filter_map { |isbn| by_isbn[isbn]&.id }.uniq

      return if ordered_ids.size < MIN_POOL

      @cache.write(pool_key(band), ordered_ids, expires_in: POOL_TTL)
    end

    private

    def pool_key(band)
      "discovery_popular:v1:#{band}"
    end

    def warming_key(band)
      "discovery_warming:v1:#{band}"
    end
  end
end
