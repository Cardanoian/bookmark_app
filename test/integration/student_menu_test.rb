require "test_helper"

# 학생 정보구조(menu_refactor 심화 PR5) — 5개 메뉴 + 홈·내 서재·독서활동 렌더.
class StudentMenuTest < ActionDispatch::IntegrationTest
  setup do
    seed_monster_species!
    @school = School.create!(name: "메뉴초등학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @student = User.create!(school: @school, classroom: @classroom, name: "메뉴학생", password: "password")
    @book = Book.create!(title: "메뉴책", author: "지은이", category: :recommended)
    @recommended_book = Book.create!(title: "공식추천책", author: "추천인", category: :recommended)
    recommendation_import = RecommendationImport.create!(
      filename: "추천.xlsx", file_digest: "student-menu-recommendations", source_title: "테스트 추천",
      imported_at: Time.current, item_count: 1, active: true
    )
    recommendation_import.book_recommendations.create!(
      book: @recommended_book, section: "어린이문학", position: 1
    )
    login_as @student
  end

  test "학생 상위 메뉴는 5개(홈·내 서재·독서활동·도감·랭킹)이고 상점·미션·독후감·게임은 상위에 없다" do
    get root_path
    assert_response :success
    # 라벨은 아이콘 span 과 분리된 label span 에 있다(모바일·데스크톱 각 1회).
    [ "홈", "내 서재", "독서활동", "도감", "랭킹" ].each do |label|
      assert_select "nav[aria-label='학생 메뉴'] span", text: label
    end
    # 제거된 상위 메뉴는 nav 에 없다.
    assert_select "nav[aria-label='학생 메뉴'] span", text: "상점", count: 0
    assert_select "nav[aria-label='학생 메뉴'] span", text: "미션", count: 0
  end

  test "홈은 추천도서·우리 반 인기 도서·책 발견 순서로 렌더한다" do
    peer = User.create!(school: @school, classroom: @classroom, name: "메뉴친구", password: "password")
    Report.create!(user: peer, classroom: @classroom, book: @book, book_title: @book.title, reviewed: true)

    get root_path
    assert_response :success
    assert_select "a[href=?]", reading_activity_path
    recommended_index = response.body.index("추천도서")
    popular_index = response.body.index("우리 반 인기 도서")
    discovery_index = response.body.index("이 책은 어때요?")
    assert recommended_index
    assert popular_index
    assert discovery_index
    assert_operator recommended_index, :<, popular_index
    assert_operator popular_index, :<, discovery_index
  end

  test "이 책은 어때요는 다른 책 보기로 다음 묶음을 순환한다" do
    12.times do |index|
      Book.create!(title: "발견책#{format('%02d', index)}", author: "발견작가", category: :recommended)
    end

    get root_path(discovery: 0)
    assert_response :success
    first_books = css_select("#book-discovery a[href*='book_id=']").map { |node| node["href"] }
    assert_equal 6, first_books.size
    assert_select "#book-discovery a", text: /다른 책 보기/

    get root_path(discovery: 1)
    assert_response :success
    next_books = css_select("#book-discovery a[href*='book_id=']").map { |node| node["href"] }
    assert_equal 6, next_books.size
    assert_not_equal first_books, next_books
  end

  test "홈은 진행 중 미션 카드를 표시한다" do
    mission = Mission.new(classroom: @classroom, title: "홈미션", reward_points: 20,
                          start_date: Date.current - 1, end_date: Date.current + 5)
    mission.mission_goals.build(goal_type: :approved_reports, target_count: 2)
    mission.save!
    mission.publish!  # @student 자동 배정
    get root_path
    assert_response :success
    assert_match "홈미션", response.body
    assert_match "진행 중인 우리 반 미션", response.body
  end

  test "내 서재는 책별 활동을 집계한다" do
    Report.create!(user: @student, classroom: @classroom, book: @book, book_title: @book.title, reviewed: true)
    @student.game_plays.create!(game_type: :quiz, book: @book, played_on: Date.current)
    get library_path
    assert_response :success
    assert_match "메뉴책", response.body
    assert_match "승인 독후감", response.body
    assert_match "게임", response.body
  end

  test "내 서재는 책 미연결 레거시 독후감을 별도로 표시한다" do
    Report.create!(user: @student, classroom: @classroom, book_id: nil, book_title: "옛날 책", reviewed: true)
    get library_path
    assert_response :success
    assert_match "책 정보가 없는 독후감", response.body
    assert_match "옛날 책", response.body
  end

  test "독서활동은 책 미선택 시 검색, 선택 시 활동 카드를 보여준다" do
    get reading_activity_path
    assert_response :success
    assert_match "먼저 읽은 책을 골라", response.body

    get reading_activity_path(book_id: @book.id)
    assert_response :success
    assert_match "메뉴책", response.body
    assert_match "독후감 쓰기", response.body
    assert_match "독서 게임", response.body
    # 게임 칩은 선택 도서로 진입한다.
    assert_select "a[href=?]", games_quiz_play_path(book_id: @book.id)
  end

  test "독서활동은 searched 캐시·미존재 book_id 를 무시하고 책 선택 상태로 되돌린다" do
    searched = Book.create!(title: "검색캐시책", category: :searched)
    get reading_activity_path(book_id: searched.id)
    assert_response :success
    assert_match "먼저 읽은 책을 골라", response.body
  end

  test "비학생은 내 서재·독서활동에 접근하면 홈으로 리다이렉트" do
    delete session_path
    teacher = User.create!(school: @school, classroom: @classroom, name: "교사", email: "menu_t@example.com", role: :teacher, password: "password")
    login_as teacher
    get library_path
    assert_redirected_to root_path
    get reading_activity_path
    assert_redirected_to root_path
  end
end
