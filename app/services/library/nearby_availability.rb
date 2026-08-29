module Library
  # 인근 도서관 대출 가능 표시의 오케스트레이션(§5.3). 학생 학교가 속한 시도의 소장 도서관 중
  # 학교 시군구(gu) 도서관만 추려 도서관별 대출 가능 여부를 정보나루로 조회한다. 권수는 표시하지 않는다.
  #
  # 무키·주소 불명·소장 0건·원격 실패 어떤 경우도 페이지를 깨지 않고 state 로 degrade 한다.
  #
  # ⚠️ **렌더 경로에서 정보나루를 호출하지 않는다**(2026-08-29 운영 실측 후 전환).
  #   실측한 지연은 우리가 조정할 수 있는 범위 밖이었다 — `libSrchByBook` 9.2~9.8초,
  #   `bookExist` 1콜 7.9~35.5초(편차 4배). 5곳 순차면 합 101초, 동시에 쏴도 8.7초다.
  #   즉 **소장목록 9.5초 + 팬아웃 8.7초 ≈ 18초**가 콜드의 정직한 비용이며, 시간예산을
  #   조여 봐야 "확인 필요"만 늘 뿐 화면이 빨라지지 않는다(조이면 품질, 늘리면 대기).
  #   그래서 `call` 은 **캐시만 읽고** 미스면 워밍 잡에 위임한 뒤 `:warming` 으로 즉시
  #   돌아온다. 실제 원격 작업은 `warm!` 이 렌더 밖에서 하고, 끝나면 Turbo Stream 으로
  #   프레임을 교체한다(PopularDiscovery 워밍 관용구와 동형).
  #
  # 소장 목록(24h)·대출여부(15min)를 분리 TTL 로 캐싱한다. cache·clock 을 주입 가능하게 해
  # 결정적 캐시/as_of 테스트를 지원한다(RateLimiter 선례).
  class NearbyAvailability
    HOLDINGS_TTL = 24.hours
    LOAN_TTL = 15.minutes
    # 소장 목록 조회 실패를 **짧게** 기억한다. 실패를 아예 기억하지 않으면 렌더가 영원히
    # 캐시 미스 → :warming 이라 학생이 "찾고 있어요"에 갇힌다(섹션이 조용히 숨는 :error 로
    # 내려가지 못함). 회복은 이 TTL 이 지나면 자동으로 다시 시도된다.
    HOLDINGS_FAIL_TTL = 10.minutes
    # 워밍이 끝났는데도 못 받아 낸 대출여부(:unknown)를 **짧게** 기억한다. 아예 기억하지 않으면
    # 렌더가 그 도서관을 영원히 캐시 미스로 보고 :warming → 워밍 → 또 :warming 을 도는
    # **무한 워밍 루프**가 된다(한 곳만 계속 느려도 섹션 전체가 안 뜬다). 이 TTL 이 지나면
    # 다시 시도하므로 회복은 여전히 열려 있다(확정값 15분보다 훨씬 짧게 잡는 이유).
    UNKNOWN_LOAN_TTL = 2.minutes
    # 실패 마커 값. 정상값(배열)·미스(nil)와 구분되는 세 번째 상태다.
    HOLDINGS_FAILED = :failed
    # 워밍 스탬피드 가드 마커 TTL. 진행 중이면 재큐잉을 스킵하고, 실패해도 자연만료로 재시도한다
    # (PopularDiscovery::WARMING_TTL 선례). 한 반이 같은 책을 동시에 열어도 잡은 1건이다.
    WARMING_TTL = 5.minutes

    # 렌더 밖(워밍 잡) 전용 상한. 실측 지연(소장목록 9.5초·동시 팬아웃 8.7초)에 여유를 얹었다.
    # 요청을 막지 않으므로 넉넉히 준다 — 여기서 조이면 캐시가 영영 안 채워진다.
    WARM_FANOUT_BUDGET = 20.seconds
    # 예산이 이보다 작으면 원격을 아예 시작하지 않는다(어차피 거두지 못할 응답).
    MIN_REMOTE_WINDOW = 0.5

    # 표시할 값 객체. state: :ok/:none/:warming/:no_key/:no_location/:error/:no_isbn.
    # libraries: [{ name:, address:, homepage:, status: }]. as_of: 표시된 도서관 fetched_at 중 최소(가장 오래된 값).
    Result = Struct.new(:state, :libraries, :as_of, keyword_init: true) do
      def ok? = state == :ok
    end

    # time_budget: **팬아웃(bookExist N콜) 전체**의 상한. 병렬이라 "N콜의 합"이 아니라 "가장 느린
    #   1콜"을 담을 크기면 된다. 워밍 잡 전용이라 기본값이 넉넉하다(렌더는 이 경로를 타지 않는다).
    def initialize(book:, school:, service: Library::Data4libraryService.new,
                   cache: Rails.cache, max_libraries: 5, time_budget: WARM_FANOUT_BUDGET,
                   now: -> { Time.current })
      @book = book
      @school = school
      @service = service
      @cache = cache
      @max_libraries = max_libraries
      @time_budget = time_budget.to_f
      @now = now
    end

    # 렌더 경로. **외부 HTTP 0** — 캐시에 다 있으면 :ok, 하나라도 비면 워밍을 걸고 :warming.
    def call
      resolve(remote: false)
    end

    # 워밍 잡 전용. 캐시를 실제로 채우고 최종 Result 를 돌려준다(잡이 그대로 방송에 싣는다).
    def warm!
      resolve(remote: true)
    end

    private

    def resolve(remote:)
      return result(:no_key) unless @service.available?

      isbn = @book&.isbn.to_s.strip
      return result(:no_isbn) if isbn.blank?

      region = Library::RegionCodes.for_school(@school)
      return result(:no_location) if region.blank?

      holdings = holdings_for(isbn, region, remote: remote)
      return enqueue_warming_and_wait if holdings == :miss
      return result(:error) if holdings.nil?

      nearby = filter_by_gu(holdings).first(@max_libraries)
      return result(:none) if nearby.empty?

      statuses = loan_statuses_for(nearby, isbn, remote: remote)
      return enqueue_warming_and_wait if statuses == :miss

      result(:ok, libraries: build_libraries(nearby, statuses), as_of: oldest_fetched_at(statuses))
    end

    # 캐시 미스를 만난 렌더의 응답. 워밍 잡을 1건만 걸고(원자 마커) 즉시 :warming 으로 돌아온다.
    # 잡이 끝나면 Turbo Stream 이 이 프레임을 완성본으로 교체한다.
    def enqueue_warming_and_wait
      acquired = @cache.write(warming_key, true, expires_in: WARMING_TTL, unless_exist: true)
      Library::NearbyLibrariesWarmJob.perform_later(@book.id, @school.id) if acquired
      result(:warming)
    end

    def warming_key = "nearby_warming:v1:#{@book&.id}:#{@school&.id}"

    # 소장 목록. 캐시 히트면 그대로, 미스면 remote 여부에 따라 실제 조회하거나 :miss 를 알린다.
    # 실패(nil)는 캐시하지 않아 다음 조회에서 다시 시도한다.
    # 저장된 []([]=진짜 빈 결과)는 캐시 히트라 외부 콜을 억제한다(캐시 히트 = 외부 콜 0).
    def holdings_for(isbn, region, remote:)
      key = "nearby_holdings:v1:#{isbn}:#{region}"
      cached = @cache.read(key)
      return nil if cached == HOLDINGS_FAILED # → :error (섹션 숨김)
      return cached unless cached.nil?
      return :miss unless remote

      fresh = @service.libraries_holding(isbn13: isbn, region: region)
      if fresh.nil?
        @cache.write(key, HOLDINGS_FAILED, expires_in: HOLDINGS_FAIL_TTL)
      else
        @cache.write(key, fresh, expires_in: HOLDINGS_TTL)
      end
      fresh
    end

    # 도서관별 대출여부. 렌더 경로에서는 **전부 캐시에 있을 때만** 값을 내고, 하나라도 비면
    # :miss 를 알려 워밍에 넘긴다 — 반쯤 채워진 "확인 필요" 화면을 내보내지 않기 위해서다.
    def loan_statuses_for(libraries, isbn, remote:)
      statuses = libraries.map { |lib| @cache.read(loan_key(lib[:code], isbn)) }
      misses = statuses.each_index.reject { |i| statuses[i].is_a?(Hash) }
      return statuses if misses.empty?
      return :miss unless remote

      fetched = fetch_loan_statuses(misses.map { |i| libraries[i][:code] }, isbn)

      misses.each_with_index do |slot, n|
        statuses[slot] = fetched[n]
        # 확정값은 15분, :unknown 은 2분만 기억한다. :unknown 은 일시 오류(HTTP·타임아웃·파싱)일 수
        # 있어 길게 캐시하면 회복이 억제되지만, **아예 캐시하지 않으면 무한 워밍 루프**가 된다
        # (렌더가 영원히 미스로 보고 :warming 을 반복). 짧게 기억해 둘 다 피한다.
        ttl = cacheable_status?(fetched[n]) ? LOAN_TTL : UNKNOWN_LOAN_TTL
        @cache.write(loan_key(libraries[slot][:code], isbn), fetched[n], expires_in: ttl)
      end
      statuses
    end

    def result(state, libraries: [], as_of: nil)
      Result.new(state: state, libraries: libraries, as_of: as_of)
    end

    # 학교 시군구(gu) 토큰 완전일치 필터(§5.3 R1). 주소를 공백 분할해 gu 와 정확히 같은 토큰이
    # 있는 도서관만 남긴다(부분문자열 include? 금지 — 대구 서구 ⊂ 달서구 오매칭 방지).
    # gu 가 nil(세종 단층제)이면 시도 전체를 유지한다.
    def filter_by_gu(holdings)
      gu = @school&.gu.to_s.strip
      return holdings if gu.blank?

      holdings.select do |lib|
        lib[:address].to_s.split(/\s+/).any? { |token| token == gu }
      end
    end

    # 원격 조회를 동시에 띄우고 시간예산 안에서 거둔다. 예산 안에 못 들어온 것만 :unknown 강등이라,
    # 느린 도서관 한 곳이 나머지를 끌고 내려가지 않는다(순차 시절의 핵심 문제).
    #
    # 예산이 처음부터 1콜도 담지 못할 만큼 작으면 **스레드를 아예 띄우지 않는다** — 어차피 못 거둘
    # 응답 때문에 정보나루에 요청만 쏘는 낭비를 막는다.
    def fetch_loan_statuses(lib_codes, isbn)
      return lib_codes.map { unknown_now } if @time_budget < MIN_REMOTE_WINDOW

      deadline = monotonic + @time_budget
      threads = lib_codes.map do |code|
        # @service 의 Faraday 커넥션을 공유한다. 요청별 상태는 블록이 받는 req 에만 쓰고 커넥션
        # 자체는 생성 후 변경하지 않으므로 동시 호출이 안전하다(Faraday 의 문서화된 사용법).
        Thread.new do
          @service.loan_status(lib_code: code, isbn13: isbn, timeout: @time_budget)
        rescue StandardError => e
          Rails.logger.warn("[nearby] loan_status thread failed for #{code}: #{e.class}: #{e.message}")
          nil
        end
      end

      threads.map do |thread|
        remaining = deadline - monotonic
        status = thread.join([ remaining, 0 ].max)&.value
        status.is_a?(Hash) ? status : unknown_now
      end
    end

    def loan_key(lib_code, isbn) = "book_loan:v1:#{lib_code}:#{isbn}"

    def unknown_now = { status: :unknown, fetched_at: @now.call }

    def cacheable_status?(status)
      status.is_a?(Hash) && %i[available unavailable].include?(status[:status])
    end

    def build_libraries(nearby, statuses)
      nearby.zip(statuses).map do |lib, status|
        { name: lib[:name], address: lib[:address], homepage: lib[:homepage],
          status: status[:status] }
      end
    end

    def oldest_fetched_at(statuses)
      statuses.filter_map { |s| s[:fetched_at] }.min
    end

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
