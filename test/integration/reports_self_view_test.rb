require "test_helper"

# 요구 2 — 자기 독후감 열람 뷰. 내 서재(책 제목)·마이페이지(활동 통계 타일)·독후감 목록 카드에서
# reports#index 로 이어지는 열람 링크(worker-1 index 필터 계약: book_id/book_title/reviewed)를 검증한다.
class ReportsSelfViewTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "열람학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @student = User.create!(school: @school, classroom: @classroom, name: "열람학생", password: "password")
    @book = Book.create!(title: "열람 테스트 책", author: "테스트저자", category: :recommended)
  end

  test "내 서재 책 제목은 그 책의 독후감 목록(book_id)으로 링크한다" do
    Report.create!(user: @student, classroom: @classroom, book_id: @book.id,
      body: "책과 연결된 독후감입니다.", reviewed: true)
    Report.create!(user: @student, classroom: @classroom, book_title: "레거시 도서",
      body: "책 정보 없는 독후감입니다.")
    login_as @student

    get library_path
    assert_response :success

    assert_select "a[href=?]", reports_path(book_id: @book.id), text: @book.title
    assert_select "a[href=?]", reports_path(book_title: "레거시 도서"), text: "레거시 도서"
  end

  test "마이페이지 활동 통계 타일이 독후감 목록(전체/승인)으로 링크한다" do
    Report.create!(user: @student, classroom: @classroom, book_id: @book.id,
      body: "승인된 독후감입니다.", reviewed: true)
    Report.create!(user: @student, classroom: @classroom, book_id: @book.id,
      body: "검토 중 독후감입니다.", reviewed: false)
    login_as @student

    get profile_path
    assert_response :success

    assert_select "a[href=?]", reports_path
    assert_select "a[href=?]", reports_path(reviewed: "true"), 1
  end

  test "독후감 목록 카드는 상세 링크와 삭제 버튼이 함께 있다" do
    report = Report.create!(user: @student, classroom: @classroom, book_id: @book.id,
      body: "목록에 뜨는 독후감입니다.", reviewed: true)
    login_as @student

    get reports_path
    assert_response :success

    assert_select "a[href=?]", report_path(report), 1
    assert_select "form[action=?] button", report_path(report), text: "삭제", count: 1
  end
end
