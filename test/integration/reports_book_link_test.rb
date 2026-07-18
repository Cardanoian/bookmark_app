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
end
