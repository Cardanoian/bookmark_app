module Library
  # 인근 도서관 대출 가능 표시의 오케스트레이션(§5.3). 학생 학교가 속한 시도의 소장 도서관 중
  # 학교 시군구(gu) 도서관만 추려 도서관별 대출 가능 여부를 정보나루로 조회한다. 권수는 표시하지 않는다.
  #
  # 무키·주소 불명·소장 0건·원격 실패 어떤 경우도 페이지를 깨지 않고 state 로 degrade 한다.
  # 소장 목록(24h)·대출여부(15min)를 분리 TTL 로 캐싱하고, bookExist 팬아웃은 시간예산 안에서만
  # 호출해 초과분은 :unknown 으로 강등한다(무한 스피너 방지). cache·clock 을 주입 가능하게 해
  # 결정적 캐시/as_of 테스트를 지원한다(RateLimiter 선례).
  class NearbyAvailability
    HOLDINGS_TTL = 24.hours
    LOAN_TTL = 15.minutes

    # 예산이 이보다 작으면 원격을 아예 시작하지 않는다(어차피 거두지 못할 응답).
    MIN_REMOTE_WINDOW = 0.5

    # 표시할 값 객체. state: :ok/:none/:no_key/:no_location/:error/:no_isbn.
    # libraries: [{ name:, address:, homepage:, status: }]. as_of: 표시된 도서관 fetched_at 중 최소(가장 오래된 값).
    Result = Struct.new(:state, :libraries, :as_of, keyword_init: true) do
      def ok? = state == :ok
    end

    # time_budget: **팬아웃(bookExist N콜) 전체**의 상한. 병렬이라 이 값은 "N콜의 합"이 아니라
    #   "가장 느린 1콜"을 담을 크기면 된다(운영 실측 1콜 2.5~3초 → 4초). 소장 목록 조회는 이
    #   예산 밖이며 `Data4libraryService::LIB_SEARCH_READ_TIMEOUT` 이 따로 상한을 건다 —
    #   그 호출이 끊기면 섹션이 통째로 사라지므로(:error) 팬아웃과 같은 잣대로 조이지 않는다.
    def initialize(book:, school:, service: Library::Data4libraryService.new,
                   cache: Rails.cache, max_libraries: 5, time_budget: 4.seconds,
                   now: -> { Time.current })
      @book = book
      @school = school
      @service = service
      @cache = cache
      @max_libraries = max_libraries
      @time_budget = time_budget.to_f
      @now = now
    end

    def call
      return result(:no_key) unless @service.available?

      isbn = @book&.isbn.to_s.strip
      return result(:no_isbn) if isbn.blank?

      region = Library::RegionCodes.for_school(@school)
      return result(:no_location) if region.blank?

      holdings = cached_holdings(isbn, region)
      return result(:error) if holdings.nil?

      nearby = filter_by_gu(holdings).first(@max_libraries)
      return result(:none) if nearby.empty?

      statuses = fan_out_loan_status(nearby, isbn)
      result(:ok, libraries: build_libraries(nearby, statuses), as_of: oldest_fetched_at(statuses))
    end

    private

    def result(state, libraries: [], as_of: nil)
      Result.new(state: state, libraries: libraries, as_of: as_of)
    end

    # 소장 목록 캐시(24h). 실패(nil)는 캐시하지 않아 다음 조회에서 다시 시도한다.
    # 저장된 []([]=진짜 빈 결과)는 캐시 히트로 외부 콜을 억제한다(캐시 히트 = 외부 콜 0).
    def cached_holdings(isbn, region)
      key = "nearby_holdings:v1:#{isbn}:#{region}"
      cached = @cache.read(key)
      return cached unless cached.nil?

      fresh = @service.libraries_holding(isbn13: isbn, region: region)
      @cache.write(key, fresh, expires_in: HOLDINGS_TTL) unless fresh.nil?
      fresh
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

    # 도서관별 대출여부 팬아웃. **캐시는 메인 스레드, 원격 호출만 병렬**이다.
    #
    # ⚠️ 왜 병렬인가 — 운영 실측(2026-08-29): `bookExist` 1콜이 **2.5~3초**다. 순차로 5곳이면
    #   12.5초 + 소장 목록 1.9초 ≈ **14.4초**로, 계획서가 실측한 14.3초와 정확히 일치한다.
    #   즉 순차인 한 "빠른 화면"과 "실제 대출 상태" 중 하나를 포기해야 한다 — 예산을 조이면
    #   대부분이 `:unknown`("확인 필요")으로 떨어지고, 늘리면 아이가 10초 넘게 기다린다.
    #   동시에 쏘면 총 소요가 **최장 1콜**로 줄어 둘 다 지킬 수 있다(실측 5.0초 → ~4.4초이면서
    #   5곳 전부 실제 상태).
    #
    # ⚠️ 스레드에서 **캐시를 건드리지 않는다.** 운영 `Rails.cache` 는 SolidCache = ActiveRecord 라
    #   스레드마다 커넥션 풀에서 체크아웃하게 되고, 요청당 5스레드면 풀이 마른다. 그래서 읽기·쓰기는
    #   메인 스레드가 하고 스레드는 순수 HTTP(Faraday)만 한다 — AR 도 오토로딩도 타지 않는다.
    def fan_out_loan_status(libraries, isbn)
      statuses = libraries.map { |lib| @cache.read(loan_key(lib[:code], isbn)) }
      misses = statuses.each_index.reject { |i| statuses[i].is_a?(Hash) }
      return statuses if misses.empty?

      fetched = fetch_loan_statuses(misses.map { |i| libraries[i][:code] }, isbn)

      misses.each_with_index do |slot, n|
        statuses[slot] = fetched[n]
        # 확정값(available/unavailable)만 캐시한다. :unknown 은 일시 오류(HTTP·타임아웃·파싱)일 수
        # 있어 캐시하면 회복이 15분간 억제된다(소장 목록의 nil 미캐시와 대칭).
        @cache.write(loan_key(libraries[slot][:code], isbn), fetched[n], expires_in: LOAN_TTL) if cacheable_status?(fetched[n])
      end
      statuses
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
