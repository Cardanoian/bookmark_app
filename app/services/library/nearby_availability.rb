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

    # 표시할 값 객체. state: :ok/:none/:no_key/:no_location/:error/:no_isbn.
    # libraries: [{ name:, address:, homepage:, status: }]. as_of: 표시된 도서관 fetched_at 중 최소(가장 오래된 값).
    Result = Struct.new(:state, :libraries, :as_of, keyword_init: true) do
      def ok? = state == :ok
    end

    def initialize(book:, school:, service: Library::Data4libraryService.new,
                   cache: Rails.cache, max_libraries: 5, time_budget: 5.seconds,
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

    # 도서관별 대출여부를 시간예산 안에서만 조회한다. 예산 초과분은 :unknown 으로 강등.
    def fan_out_loan_status(libraries, isbn)
      started = monotonic
      libraries.map do |lib|
        if (monotonic - started) >= @time_budget
          { status: :unknown, fetched_at: @now.call }
        else
          cached_loan_status(lib[:code], isbn)
        end
      end
    end

    # 대출여부 캐시(15min). {status:, fetched_at:} 통째 캐시라 캐시 히트 시에도 fetched_at 이
    # 보존돼 as_of("○분 기준")가 정직하게 표기된다. :unknown 은 일시 오류(HTTP·타임아웃·파싱)일 수
    # 있어 캐시하지 않는다 — 회복 후 다음 조회에서 다시 시도(소장 목록의 nil 미캐시와 대칭).
    # 확정값(available/unavailable)만 캐시한다.
    def cached_loan_status(lib_code, isbn)
      key = "book_loan:v1:#{lib_code}:#{isbn}"
      cached = @cache.read(key)
      return cached if cached.is_a?(Hash)

      fresh = @service.loan_status(lib_code: lib_code, isbn13: isbn)
      @cache.write(key, fresh, expires_in: LOAN_TTL) if cacheable_status?(fresh)
      fresh
    end

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
