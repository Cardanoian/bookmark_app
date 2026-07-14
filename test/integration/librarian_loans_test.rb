require "test_helper"

# P6.5 사서 인기대출: 수동 입력 · 정보나루 동기화(무키 폴백/스텁 upsert) · CSV 업로드 파싱.
class LibrarianLoansTest < ActionDispatch::IntegrationTest
  # 네트워크 없이 available? 를 흉내내는 스텁 서비스.
  class StubData4library
    def initialize(loans, last_error: nil)
      @loans = loans
      @last_error = last_error
    end
    def available? = true
    def popular_loans(*, **) = @loans
    def last_error = @last_error
  end

  setup do
    @school = School.create!(name: "대출학교")
    @librarian = User.create!(school: @school, name: "대출사서", role: :librarian, password: "password")
  end

  test "index lists loans for this school and national" do
    LibraryLoan.create!(school: @school, book_title: "학교대출책", count: 12, period: "2026-07")
    login_as @librarian
    get librarian_loans_path
    assert_response :success
    assert_match "학교대출책", response.body
  end

  test "create adds a manual loan record scoped to the school" do
    login_as @librarian
    assert_difference -> { LibraryLoan.count }, 1 do
      post librarian_loans_path, params: { library_loan: { book_title: "수동책", count: 7, period: "2026-07" } }
    end
    assert_equal @school.id, LibraryLoan.find_by(book_title: "수동책").school_id
  end

  test "sync_data4library without a key shows a graceful CSV-fallback notice" do
    login_as @librarian
    assert_no_difference -> { LibraryLoan.count } do
      post sync_data4library_librarian_loans_path
    end
    follow_redirect!
    assert_match "CSV", response.body
  end

  test "sync_data4library with an available client upserts national loans" do
    swap_service(StubData4library.new([ { book_title: "정보나루책", isbn: "9781111111111", count: 555 } ])) do
      login_as @librarian
      assert_difference -> { LibraryLoan.where(source: :data4library).count }, 1 do
        post sync_data4library_librarian_loans_path
      end
    end
    loan = LibraryLoan.find_by(book_title: "정보나루책")
    assert loan
    assert_nil loan.school_id, "정보나루 인기대출은 전국(NULL) 스코프여야 한다"
    assert_equal 555, loan.count
  end

  test "sync_data4library surfaces an API failure instead of a misleading 0-record success" do
    swap_service(StubData4library.new([], last_error: "정보나루 응답 오류 (HTTP 500)")) do
      login_as @librarian
      assert_no_difference -> { LibraryLoan.count } do
        post sync_data4library_librarian_loans_path
      end
      follow_redirect!
    end
    assert_match "동기화 실패", response.body
  end

  test "import_csv parses a CSV upload into loan rows (manual RFC 4180 parse)" do
    csv = "도서명,대출건수,기간\n\"어린 왕자\",42,2026-07\n마당을 나온 암탉,30,2026-07\n"
    login_as @librarian
    assert_difference -> { LibraryLoan.count }, 2 do
      post import_csv_librarian_loans_path, params: { file: upload(csv) }
    end
    assert_equal 42, LibraryLoan.find_by(book_title: "어린 왕자").count
  end

  test "import_csv is idempotent on re-upload (upsert by school+title+period)" do
    csv = "도서명,대출건수,기간\n어린 왕자,42,2026-07\n"
    login_as @librarian
    post import_csv_librarian_loans_path, params: { file: upload(csv) }
    assert_no_difference -> { LibraryLoan.count } do
      post import_csv_librarian_loans_path, params: { file: upload(csv) }
    end
  end

  private

  def upload(content)
    file = Tempfile.new([ "loans", ".csv" ])
    file.write(content)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "text/csv")
  end

  # Library::Data4libraryService.new 를 스텁으로 교체(미니테스트 mock 부재 → 싱글턴 스왑).
  def swap_service(stub)
    original = Library::Data4libraryService.method(:new)
    Library::Data4libraryService.define_singleton_method(:new) { |*| stub }
    yield
  ensure
    Library::Data4libraryService.singleton_class.send(:remove_method, :new)
    Library::Data4libraryService.define_singleton_method(:new, original)
  end
end
