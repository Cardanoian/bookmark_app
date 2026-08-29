require "test_helper"

# 인근 도서관 대출 가능 표시 — 독서활동 화면의 Turbo Frame lazy-load 액션(§7 수용기준).
class ReadingActivitiesNearbyTest < ActionDispatch::IntegrationTest
  ISBN = "9788949140926".freeze

  # 네트워크 없는 스텁 정보나루 서비스. holdings 호출 수를 세어 lazy-load 를 검증한다.
  class StubData4library
    attr_reader :holdings_calls

    def initialize(available: true, holdings: [], loans: {})
      @available = available
      @holdings = holdings
      @loans = loans
      @holdings_calls = 0
    end

    def available? = @available

    def libraries_holding(isbn13:, region:, page_size: 1000, timeout: nil)
      @holdings_calls += 1
      @holdings
    end

    def loan_status(lib_code:, isbn13:, timeout: nil)
      @loans.fetch(lib_code, { status: :unknown, fetched_at: Time.current })
    end
  end

  setup do
    @school = School.create!(name: "인근초등학교", region: "서울특별시교육청", gu: "노원구",
                             address: "서울특별시 노원구 상계로 1")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @student = User.create!(school: @school, classroom: @classroom, name: "인근학생", password: "password")
    @book = Book.create!(title: "인근책", author: "지은이", category: :recommended, isbn: ISBN)
    login_as @student
  end

  def lib(code, address, name: nil)
    { code: code, name: name || "도서관#{code}", address: address,
      tel: "", homepage: "", latitude: "", longitude: "" }
  end

  test "show renders the lazy frame below the activity cards without calling the API (criterion 7)" do
    stub = StubData4library.new(holdings: [ lib("A", "서울특별시 노원구 상계로 1") ])
    swap_service(stub) do
      get reading_activity_path(book_id: @book.id)
    end

    assert_response :success
    assert_select ".page-shell.page-shell-wide", count: 1,
      message: "독서활동 화면은 다른 학생 상위 메뉴와 같은 넓은 페이지 셸을 사용한다"
    assert_equal 0, stub.holdings_calls, "첫 show 렌더는 외부 API 를 호출하지 않는다(lazy frame)"
    # 단수 라우트 헬퍼가 book_id 를 쿼리로 실은 src 로 정상 렌더된다.
    assert_select "turbo-frame#nearby_libraries[src=?]",
                  nearby_libraries_reading_activity_path(book_id: @book.id)
    # 프레임은 활동 카드(독서 게임) 아래에 위치한다.
    assert_operator response.body.index("독서 게임"), :<, response.body.index("nearby_libraries")
  end

  # 렌더는 캐시만 읽고 미스면 워밍 잡에 위임한다(정보나루가 소장목록 9.5초·대출조회 1콜
  # 8~35초라 요청 안에서 감당할 수 없다). 그래서 상태 분기를 보려면 **워밍이 먼저 돌아야** 한다.

  test "캐시가 비면 워밍 잡을 걸고 '찾고 있어요'를 즉시 돌려준다" do
    stub = StubData4library.new(holdings: [ lib("A", "서울특별시 노원구 상계로 1") ])

    assert_enqueued_with(job: Library::NearbyLibrariesWarmJob, args: [ @book.id, @school.id ]) do
      swap_service(stub) { get nearby_libraries_reading_activity_path(book_id: @book.id) }
    end

    assert_response :success
    assert_match "가까운 도서관을 찾고 있어요", response.body
    assert_equal 0, stub.holdings_calls, "렌더 경로는 정보나루를 부르지 않는다"
    # 구독이 없으면 학생은 워밍이 끝나도 화면이 바뀌지 않아 영영 기다린다.
    assert_select "turbo-frame#nearby_libraries turbo-cable-stream-source", 1
  end

  test "nearby_libraries lists holding libraries with available/busy badges (criterion 1)" do
    holdings = [ lib("A", "서울특별시 노원구 상계로 1", name: "노원도서관"),
                 lib("B", "서울특별시 노원구 월계로 2", name: "월계도서관") ]
    loans = { "A" => { status: :available, fetched_at: Time.current },
              "B" => { status: :unavailable, fetched_at: Time.current } }

    with_warmed_cache(StubData4library.new(holdings: holdings, loans: loans)) do
      get nearby_libraries_reading_activity_path(book_id: @book.id)
    end

    assert_response :success
    assert_select "turbo-frame#nearby_libraries"
    assert_match "노원도서관", response.body
    assert_match "월계도서관", response.body
    assert_match "대출 가능", response.body
    assert_match "대출 중", response.body
    assert_no_match "찾고 있어요", response.body, "워밍이 끝났으면 대기 문구가 남지 않는다"
  end

  test "nearby_libraries shows an empty state when all holdings are in a different gu (criterion 2)" do
    holdings = [ lib("A", "서울특별시 강남구 테헤란로 1") ]

    with_warmed_cache(StubData4library.new(holdings: holdings)) do
      get nearby_libraries_reading_activity_path(book_id: @book.id)
    end

    assert_response :success
    assert_match "빌릴 수 있는 도서관이 없어요", response.body
  end

  test "nearby_libraries hides the section without a key and the page stays healthy (criterion 3)" do
    swap_service(StubData4library.new(available: false)) do
      get nearby_libraries_reading_activity_path(book_id: @book.id)
    end

    assert_response :success
    assert_no_match "우리 학교 근처", response.body
    assert_no_match "없어요", response.body
    assert_select "turbo-frame#nearby_libraries"
  end

  test "nearby_libraries hides the section on a remote failure with no exception (criterion 4)" do
    # 실패는 **짧게 기억**해야 한다. 아예 기억하지 않으면 렌더가 영원히 캐시 미스 → :warming
    # 이라 학생이 "찾고 있어요"에 갇힌다(섹션이 조용히 숨는 :error 로 내려가지 못함).
    with_warmed_cache(StubData4library.new(holdings: nil)) do # libraries_holding → nil = 원격 실패
      get nearby_libraries_reading_activity_path(book_id: @book.id)
    end

    assert_response :success
    assert_no_match "우리 학교 근처", response.body
    assert_no_match "없어요", response.body
    assert_no_match "찾고 있어요", response.body, "실패는 무한 대기가 아니라 섹션 숨김으로 끝난다"
  end

  test "nearby_libraries degrades to a staff notice when the school location is unresolvable (criterion 5)" do
    @school.update_columns(region: "", address: "")
    swap_service(StubData4library.new(holdings: [ lib("A", "서울특별시 노원구 상계로 1") ])) do
      get nearby_libraries_reading_activity_path(book_id: @book.id)
    end

    assert_response :success
    assert_match "학교 주소 정보가 없어", response.body
  end

  test "a non-student is redirected away from nearby_libraries (criterion 6)" do
    delete session_path
    teacher = User.create!(school: @school, classroom: @classroom, name: "인근교사",
                           email: "nearby_t@example.com", role: :teacher, password: "password")
    login_as teacher
    get nearby_libraries_reading_activity_path(book_id: @book.id)
    assert_redirected_to root_path
  end

  test "nearby_libraries renders an empty frame for a searched/missing book_id (defensive)" do
    searched = Book.create!(title: "검색캐시책", category: :searched)
    swap_service(StubData4library.new(holdings: [ lib("A", "서울특별시 노원구 상계로 1") ])) do
      get nearby_libraries_reading_activity_path(book_id: searched.id)
    end

    assert_response :success
    assert_select "turbo-frame#nearby_libraries"
    assert_no_match "우리 학교 근처", response.body
  end

  private

  # 워밍 잡을 먼저 돌려 캐시를 채운 뒤 블록(렌더)을 실행한다.
  #
  # ⚠️ test 환경의 `Rails.cache` 는 `:null_store` 라 아무것도 남지 않는다 — 그대로 두면 렌더가
  #   항상 :warming 이라 :ok/:none/:error 분기를 볼 수 없다. 이 헬퍼 안에서만 MemoryStore 로 바꾼다.
  def with_warmed_cache(stub)
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    swap_service(stub) do
      Library::NearbyLibrariesWarmJob.perform_now(@book.id, @school.id)
      yield
    end
  ensure
    Rails.cache = original
  end

  # Library::Data4libraryService.new 를 스텁으로 교체(NearbyAvailability 기본 service: 주입 경로).
  def swap_service(stub)
    original = Library::Data4libraryService.method(:new)
    Library::Data4libraryService.define_singleton_method(:new) { |*| stub }
    yield
  ensure
    Library::Data4libraryService.singleton_class.send(:remove_method, :new)
    Library::Data4libraryService.define_singleton_method(:new, original)
  end
end
