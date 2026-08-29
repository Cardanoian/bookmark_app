require "test_helper"

# 인근 도서관 워밍 잡. 렌더 경로가 캐시만 읽도록 바뀌면서, **이 잡이 돌지 않으면 학생은
# 영영 "가까운 도서관을 찾고 있어요"만 본다.** 잡이 캐시를 실제로 채우는지와, 다 채운 뒤
# 프레임을 교체하는 방송이 나가는지를 함께 고정한다(둘 중 하나만 깨져도 화면이 멈춘다).
class Library::NearbyLibrariesWarmJobTest < ActiveSupport::TestCase
  ISBN = "9788949140926".freeze

  class StubService
    attr_reader :holdings_calls, :loan_calls

    def initialize(available: true, holdings: [], loans: {})
      @available = available
      @holdings = holdings
      @loans = loans
      @holdings_calls = 0
      @loan_calls = 0
      @lock = Mutex.new
    end

    def available? = @available

    def libraries_holding(isbn13:, region:, page_size: 1000, timeout: nil)
      @lock.synchronize { @holdings_calls += 1 }
      @holdings
    end

    def loan_status(lib_code:, isbn13:, timeout: nil)
      @lock.synchronize { @loan_calls += 1 }
      @loans.fetch(lib_code, { status: :unknown, fetched_at: Time.current })
    end
  end

  setup do
    @school = School.create!(name: "워밍잡초", region: "서울특별시교육청", gu: "노원구",
                             address: "서울특별시 노원구 상계로 1")
    @book = Book.create!(title: "워밍잡책", author: "지은이", category: :recommended, isbn: ISBN)
    @holdings = [ { code: "A", name: "노원도서관", address: "서울특별시 노원구 상계로 1",
                    tel: "", homepage: "", latitude: "", longitude: "" } ]
    @loans = { "A" => { status: :available, fetched_at: Time.current } }
  end

  test "잡이 캐시를 채워, 이후 렌더가 외부 콜 0 으로 :ok 를 낸다" do
    with_memory_cache do
      warm = StubService.new(holdings: @holdings, loans: @loans)
      swap_service(warm) { Library::NearbyLibrariesWarmJob.perform_now(@book.id, @school.id) }
      assert_equal 1, warm.holdings_calls
      assert_equal 1, warm.loan_calls

      # 렌더가 원격을 부르면 :error 로 드러나는 스텁을 쓴다.
      reader = StubService.new(holdings: nil)
      result = Library::NearbyAvailability.new(book: @book, school: @school, service: reader).call

      assert_equal :ok, result.state
      assert_equal :available, result.libraries.first[:status]
      assert_equal 0, reader.holdings_calls
      assert_equal 0, reader.loan_calls
    end
  end

  test "워밍이 끝나면 그 학교·책 프레임을 교체하는 방송이 나간다" do
    with_memory_cache do
      streams = capture_turbo_stream_broadcasts([ @school.id, @book.id, :nearby_libraries ]) do
        swap_service(StubService.new(holdings: @holdings, loans: @loans)) do
          Library::NearbyLibrariesWarmJob.perform_now(@book.id, @school.id)
        end
      end

      assert_equal 1, streams.size
      assert_equal "replace", streams.first["action"]
      # target 은 파셜이 감싸는 turbo_frame_tag 와 같은 id 여야 프레임이 제자리 교체된다.
      assert_equal "nearby_libraries", streams.first["target"]
      assert_includes streams.first.to_html, "노원도서관"
      assert_not_includes streams.first.to_html, "찾고 있어요"
    end
  end

  test "방송이 실패해도 이미 채운 캐시를 되돌리지 않는다" do
    with_memory_cache do
      job = Library::NearbyLibrariesWarmJob.new
      job.define_singleton_method(:broadcast) { |*| raise "boom broadcast" }

      swap_service(StubService.new(holdings: @holdings, loans: @loans)) do
        assert_nothing_raised { job.perform(@book.id, @school.id) }
      end

      reader = StubService.new(holdings: nil)
      result = Library::NearbyAvailability.new(book: @book, school: @school, service: reader).call
      assert_equal :ok, result.state, "방송 실패는 워밍 결과를 무르지 않는다"
    end
  end

  test "삭제된 책·학교면 조용히 끝난다" do
    swap_service(StubService.new) do
      assert_nothing_raised do
        Library::NearbyLibrariesWarmJob.perform_now(@book.id, -1)
        Library::NearbyLibrariesWarmJob.perform_now(-1, @school.id)
      end
    end
  end

  test "무키면 원격을 부르지 않고 :no_key 상태를 방송한다" do
    with_memory_cache do
      stub = StubService.new(available: false)
      streams = capture_turbo_stream_broadcasts([ @school.id, @book.id, :nearby_libraries ]) do
        swap_service(stub) { Library::NearbyLibrariesWarmJob.perform_now(@book.id, @school.id) }
      end

      assert_equal 0, stub.holdings_calls
      assert_equal 1, streams.size, "무키여도 프레임은 대기 문구에서 벗어나야 한다"
      assert_not_includes streams.first.to_html, "찾고 있어요"
    end
  end

  private

  # test 환경 기본 캐시는 :null_store 라 워밍이 아무것도 남기지 못한다.
  def with_memory_cache
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    yield
  ensure
    Rails.cache = original
  end

  def swap_service(stub)
    original = Library::Data4libraryService.method(:new)
    Library::Data4libraryService.define_singleton_method(:new) { |*| stub }
    yield
  ensure
    Library::Data4libraryService.singleton_class.send(:remove_method, :new)
    Library::Data4libraryService.define_singleton_method(:new, original)
  end
end
