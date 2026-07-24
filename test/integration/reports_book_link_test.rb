require "test_helper"

# WS-D — 독후감 도서 자동완성 연결. DB 도서를 고르면 report.book 에 연결되고 표지가 뜨며,
# 안 고르거나 무효 id 면 book_title 자유텍스트 폴백으로 저장된다(무효 참조 차단).
class ReportsBookLinkTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @school = School.create!(name: "책연결학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @teacher = User.create!(school: @school, classroom: @classroom, name: "책연결담임", role: :teacher, password: "password")
    @classroom.update!(teacher: @teacher)
    @student = User.create!(school: @school, classroom: @classroom, name: "책연결학생", password: "password")
    @book = Book.create!(title: "긴긴밤", author: "루리", publisher: "문학동네",
                         cover_url: "https://example.com/ginginbam.jpg", category: :recommended)
  end

  test "DB 도서를 선택하면 report.book 에 연결되고 상세에 표지가 뜬다" do
    login_as @student

    post reports_path, params: { report: {
      book_id: @book.id, book_title: @book.title, body: "긴긴밤을 읽고 우정을 느꼈다.", input_mode: "keyboard"
    } }

    report = @student.reports.order(:created_at).last
    assert_equal @book.id, report.book_id, "선택한 book_id 가 연결돼야 한다"
    assert_redirected_to report_path(report)

    get report_path(report)
    assert_response :success
    assert_select "img[src=?]", @book.cover_url
  end

  test "도서를 고르지 않고 자유텍스트만 입력하면 book_title 폴백으로 저장된다" do
    login_as @student

    post reports_path, params: { report: {
      book_id: "", book_title: "직접 적은 책 제목", body: "본문입니다.", input_mode: "keyboard"
    } }

    report = @student.reports.order(:created_at).last
    assert_nil report.book_id, "빈 book_id 는 nil 로 저장된다"
    assert_equal "직접 적은 책 제목", report.book_title
  end

  test "실존하지 않는 book_id 는 무시하고 book_title 폴백으로 저장된다" do
    login_as @student

    post reports_path, params: { report: {
      book_id: 999_999, book_title: "폴백 책 제목", body: "본문입니다.", input_mode: "keyboard"
    } }

    report = @student.reports.order(:created_at).last
    assert_nil report.book_id, "실존하지 않는 book_id 는 무시(nil)된다"
    assert_equal "폴백 책 제목", report.book_title
  end

  # 제출 시 원격 등록(캐시-우선·save 밖 비차단) — remote_isbn + 빈 book_id 로 제출하면
  # SearchService#register 가 캐시 메타로 Book 을 등록하고 report.book_id 로 링크한다.
  test "remote_isbn 과 빈 book_id 로 제출하면 원격 책을 등록해 report.book_id 에 링크한다" do
    login_as @student

    isbn = "9791234567896"
    with_memory_cache do
      # 검색 버튼 시점에 서버가 적재해 두는 메타를 시드(클라 payload 아님) → register 가 재사용.
      Rails.cache.write("book_meta:#{isbn}", {
        id: nil, title: "서버 원격책", author: "원격저자", publisher: "원격출판",
        thumbnail: "https://example.com/remote.jpg", isbn: isbn, description: "설명"
      })

      assert_difference "Book.count", 1, "캐시 히트로 새 Book 이 등록된다" do
        post reports_path, params: { report: {
          book_id: "", remote_isbn: isbn, book_title: "학생이 적은 제목",
          body: "원격으로 고른 책을 읽고.", input_mode: "keyboard"
        } }
      end
    end

    report = @student.reports.order(:created_at).last
    book = Book.find_by(isbn: isbn)
    assert_not_nil book, "remote_isbn 으로 Book 이 등록돼야 한다"
    assert_equal book.id, report.book_id, "등록된 원격 책이 report.book_id 로 링크돼야 한다"
    assert_equal "서버 원격책", book.title, "저장된 title 은 서버 캐시 메타에서 온다 — 클라 payload 아님"
    assert_redirected_to report_path(report)
  end

  # 작성 즉시 정식 등록(사용자 결정) — 검색(remote_isbn)으로 고른 책에 독후감을 쓰면 그 책은
  # searched 캐시가 아니라 정식 카탈로그(recommended)로 즉시 승격돼 검색·게임·발견에 바로 노출된다.
  test "remote_isbn 으로 등록된 책은 작성 즉시 정식 도서(recommended)로 승격된다" do
    login_as @student

    isbn = "9791234567896"
    with_memory_cache do
      Rails.cache.write("book_meta:#{isbn}", {
        id: nil, title: "검색으로 찾은 책", author: "저자", publisher: "출판",
        thumbnail: "https://example.com/x.jpg", isbn: isbn, description: "설명"
      })

      post reports_path, params: { report: {
        book_id: "", remote_isbn: isbn, book_title: "학생이 적은 제목",
        body: "검색으로 찾은 책을 읽고.", input_mode: "keyboard"
      } }
    end

    book = Book.find_by(isbn: isbn)
    assert_not_nil book, "remote_isbn 으로 Book 이 등록돼야 한다"
    assert book.recommended?, "검색해서 독후감을 쓴 책은 작성 즉시 정식 도서(recommended)로 등록돼야 한다"
  end

  # 비차단 계약 — register 가 nil(무키·캐시 미스)이어도 save 를 막거나 롤백하지 않고
  # book_title 자유텍스트 폴백으로 저장된다. 테스트 환경은 무키 + null_store 라 register→nil.
  test "remote_isbn 등록 실패면 book_title 폴백으로 저장되고 save 는 롤백되지 않는다" do
    login_as @student

    assert_no_difference "Book.count", "무키/캐시 미스면 Book 을 만들지 않는다" do
      post reports_path, params: { report: {
        book_id: "", remote_isbn: "9780000000002", book_title: "폴백 텍스트 제목",
        body: "본문입니다.", input_mode: "keyboard"
      } }
    end

    report = @student.reports.order(:created_at).last
    assert_not_nil report, "register nil 이어도 save 는 성공한다(롤백 0)"
    assert_nil report.book_id, "등록 실패 시 book_id 는 공란"
    assert_equal "폴백 텍스트 제목", report.book_title
    assert_redirected_to report_path(report)
  end

  # 정상 경로 유지 — 유효 book_id + 본문 제출은 first_review 첨삭(AiReviewJob)을 예약한다.
  # book_id 가 있으면 remote_isbn 등록 경로는 발동하지 않는다.
  test "유효 book_id 정상 제출은 AiReviewJob 을 예약한다" do
    login_as @student

    assert_enqueued_with(job: AiReviewJob) do
      post reports_path, params: { report: {
        book_id: @book.id, book_title: @book.title, body: "긴긴밤을 읽고.", input_mode: "keyboard"
      } }
    end
  end

  private

  # test 환경 cache 는 null_store 라 write/read 가 no-op. 캐시-우선 등록 경로를 검증하려면
  # 실제 저장되는 memory store 로 잠시 교체한다(search_service_test.rb 관례).
  def with_memory_cache
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    yield
  ensure
    Rails.cache = original
  end
end
