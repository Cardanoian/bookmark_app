require "test_helper"

# WS-C — 게임 카탈로그 재구성: 전량 도서 로드(@books) 제거 + 폼리스 도서 검색(book-search)
# + book:selected 로 활성화되는 5종 게임 칩. 카탈로그가 도서 존재에 의존하지 않음을 회귀 검증한다.
class GamesCatalogTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "카탈로그학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @student = User.create!(school: @school, classroom: @classroom, name: "카탈로그학생", password: "password")
  end

  test "catalog index renders for a logged-in student" do
    login_as @student
    get games_catalog_path
    assert_response :success
  end

  # 폼리스 도서 검색 + 게임 칩이 렌더되고, 도서를 미리 로드하지 않는다(전량 로드 제거).
  test "catalog renders the formless book search and five game chips" do
    login_as @student
    get games_catalog_path
    assert_response :success

    assert_select "[data-controller~=book-search][data-controller~=games-catalog]"
    assert_select "[data-action*='book:selected->games-catalog#bookSelected']"
    assert_select "input[data-book-search-target=input]"
    assert_select "ul[data-book-search-target=results]"
    assert_select "[data-games-catalog-target=chip]", count: 5
  end

  # 회귀 — 카탈로그가 도서 존재에 의존하지 않는다(setup 에서 도서를 하나도 만들지 않음).
  test "catalog does not require any book to exist" do
    assert_equal 0, Book.count
    login_as @student
    get games_catalog_path
    assert_response :success
    assert_select "[data-games-catalog-target=chip]", count: 5
  end
end
