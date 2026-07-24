require "test_helper"

# P6.5 사서 대시보드: 인기대출(학교+전국) · 이달의 책·행사 · 경계 인가.
class LibrarianDashboardTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "대시보드학교")
    @librarian = User.create!(school: @school, name: "대시보드사서", role: :librarian, password: "password")
    LibraryLoan.create!(school: @school, book_title: "학교인기책", count: 30, source: :csv, period: "2026-07")
    LibraryLoan.create!(school: nil, book_title: "전국인기책", count: 900, source: :data4library, period: "2026-07")
    LibraryEvent.create!(school: @school, title: "이달의 책 행사")
  end

  test "renders popular loans and events for the librarian's school" do
    login_as @librarian
    get librarian_dashboard_path
    assert_response :success
    assert_match "학교인기책", response.body
    assert_match "전국인기책", response.body
    assert_match "이달의 책 행사", response.body
  end

  test "a student is forbidden from the librarian dashboard" do
    classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    student = User.create!(school: @school, classroom: classroom, name: "대시학생", password: "password")
    login_as student
    get librarian_dashboard_path
    assert_response :forbidden
  end

  private
end
