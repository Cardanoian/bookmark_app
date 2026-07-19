require "test_helper"

class DashboardAccessTest < ActionDispatch::IntegrationTest
  test "unauthenticated request to root redirects to login" do
    get root_path
    assert_redirected_to new_session_path
  end

  test "authenticated user can reach the dashboard" do
    school = School.create!(name: "대시초등학교")
    classroom = Classroom.create!(school: school, grade: 3, class_no: 1)
    student = User.create!(school: school, classroom: classroom, name: "대시학생", password: "password")

    login_as student
    get root_path

    assert_response :success
    assert_match "대시학생", response.body
    assert_select "#student-overview.grid.lg\\:grid-cols-2.items-stretch" do
      assert_select "> div.h-full", count: 2
      assert_select "> div.h-full:first-child > .card-feature.h-full", count: 1
      assert_select "#student-growth-summary.stat-card.h-full", count: 1
    end
    assert_no_match "보유 포인트와 경험치", response.body
    assert_select "#student-growth-summary > div.flex > [data-growth-stat]", count: 2
    assert_select "#student-growth-summary [data-growth-stat='experience'].flex-1:first-child" do
      assert_select ".stat-card__value", text: "0XP"
      assert_select ".badge", text: /Lv\.1/
    end
    assert_select "#student-growth-summary [data-growth-stat='points'].flex-1:last-child .stat-card__value", text: "0P"
    assert_no_match "포인트를 써도 유지돼요", response.body
  end

  # 추천도서가 한 화면(6권)보다 많으면 "다른 책 보기"로 다음 6권을 순환한다(발견 섹션과 동형).
  test "student home shows a cycle button and rotates the recommended books" do
    school = School.create!(name: "추천초등학교")
    classroom = Classroom.create!(school: school, grade: 3, class_no: 1)
    student = User.create!(school: school, classroom: classroom, name: "추천학생", password: "password")
    import = RecommendationImport.create!(filename: "rec.xlsx", file_digest: "digest-#{SecureRandom.hex(8)}",
                                          imported_at: Time.current, active: true, item_count: 8)
    8.times do |i|
      book = Book.create!(title: "추천책#{format('%02d', i + 1)}", category: :recommended)
      import.book_recommendations.create!(book: book, position: i + 1, section: "children")
    end

    login_as student
    get root_path
    assert_response :success
    assert_match "다른 책 보기", response.body

    titles = ->(body) { (1..8).select { |i| body.include?("추천책#{format('%02d', i)}") } }
    first_page = titles.call(response.body)
    assert_equal 6, first_page.length # 8권 중 6권만 노출

    get root_path(recommend: 1)
    assert_response :success
    assert_not_equal first_page, titles.call(response.body) # 순환 시 묶음이 달라짐
  end

  # 추천도서가 6권 이하면 순환할 것이 없어 "다른 책 보기"를 숨긴다.
  test "student home hides the cycle button when recommendations fit one screen" do
    school = School.create!(name: "소량추천초등학교")
    classroom = Classroom.create!(school: school, grade: 3, class_no: 1)
    student = User.create!(school: school, classroom: classroom, name: "소량학생", password: "password")
    import = RecommendationImport.create!(filename: "rec2.xlsx", file_digest: "digest-#{SecureRandom.hex(8)}",
                                          imported_at: Time.current, active: true, item_count: 3)
    3.times do |i|
      book = Book.create!(title: "소량책#{i + 1}", category: :recommended)
      import.book_recommendations.create!(book: book, position: i + 1, section: "children")
    end

    login_as student
    get root_path
    assert_response :success
    assert_match "소량책1", response.body
    assert_no_match(/다른 책 보기/, response.body)
  end
end
