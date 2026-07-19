require "test_helper"

# 독후감 목록(index) 필터 — 자기 서재에서 특정 책/승인분/레거시 제목별로 독후감을 좁혀 본다.
# 필터는 반드시 policy_scope 위에만 얹혀 위조 파라미터로 남의 글이 새지 않아야 하고, 필터·페이지가
# 함께 유지돼야 한다. book_title 은 레거시(book_id nil) 독후감을 정규화된 제목으로 조회한다.
class ReportsIndexFiltersTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @school = School.create!(name: "필터학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @teacher = User.create!(school: @school, classroom: @classroom, name: "필터담임", role: :teacher, password: "password")
    @classroom.update!(teacher: @teacher)
    @student = User.create!(school: @school, classroom: @classroom, name: "필터학생", password: "password")
    @book = Book.create!(title: "긴긴밤", author: "루리")
    @other_book = Book.create!(title: "마당을 나온 암탉", author: "황선미")
  end

  test "book_id 필터는 그 책의 독후감만 보여 준다" do
    create_report(book: @book, body: "긴긴밤 감상 본문")
    create_report(book: @other_book, body: "암탉 감상 본문")

    login_as @student
    get reports_path(book_id: @book.id)

    assert_response :success
    assert_match "긴긴밤 감상 본문", response.body
    assert_no_match "암탉 감상 본문", response.body
    assert_match "『긴긴밤』 독후감", response.body
  end

  test "reviewed=true 필터는 교사 승인분만 보여 준다" do
    create_report(book: @book, body: "승인된 본문입니다", reviewed: true)
    create_report(book: @book, body: "아직 미승인 본문", reviewed: false)

    login_as @student
    get reports_path(reviewed: "true")

    assert_response :success
    assert_match "승인된 본문입니다", response.body
    assert_no_match "아직 미승인 본문", response.body
    assert_match "선생님 확인 독후감", response.body
  end

  test "book_title 필터는 레거시(book_id nil) 독후감만 보여 준다" do
    create_report(book: nil, book_title: "레거시 제목", body: "레거시 본문입니다")
    create_report(book: nil, book_title: "다른 레거시", body: "다른 본문입니다")

    login_as @student
    get reports_path(book_title: "레거시 제목")

    assert_response :success
    assert_match "레거시 본문입니다", response.body
    assert_no_match "다른 본문입니다", response.body
    assert_match "책 정보 없음", response.body
  end

  test "이중 공백 레거시 제목은 정규화되어 정규화된 제목으로 조회된다" do
    report = create_report(book: nil, book_title: "이중  공백  제목", body: "이중공백 본문")
    assert_equal "이중 공백 제목", report.reload.book_title, "저장 시 squish 로 정규화된다"

    login_as @student
    get reports_path(book_title: "이중 공백 제목")

    assert_response :success
    assert_match "이중공백 본문", response.body
    assert_match "『이중 공백 제목』 독후감", response.body
  end

  test "book_id 와 reviewed 를 함께 걸면 그 책의 승인분만 보여 준다" do
    create_report(book: @book, body: "긴긴밤 승인 본문", reviewed: true)
    create_report(book: @book, body: "긴긴밤 미승인 본문", reviewed: false)
    create_report(book: @other_book, body: "암탉 승인 본문", reviewed: true)

    login_as @student
    get reports_path(book_id: @book.id, reviewed: "true")

    assert_response :success
    assert_match "긴긴밤 승인 본문", response.body
    assert_no_match "긴긴밤 미승인 본문", response.body, "같은 책이라도 미승인분은 제외"
    assert_no_match "암탉 승인 본문", response.body, "다른 책의 승인분도 제외"
    assert_select "article.card", 1, "긴긴밤 승인분 1건만 남는다"
  end

  test "다른 학생의 독후감 book_id 로 요청해도 노출되지 않는다(policy_scope)" do
    other_student = User.create!(school: @school, classroom: @classroom, name: "남의학생", password: "password")
    Report.create!(user: other_student, classroom: @classroom, book: @book, body: "남의비밀본문")

    login_as @student
    get reports_path(book_id: @book.id)

    assert_response :success
    assert_no_match "남의비밀본문", response.body, "위조 book_id 로도 남의 글은 안 보인다"
    assert_select "article.card", 0, "본인 글이 없으므로 카드 0건(남의 글 노출 없음)"
  end

  test "필터가 2페이지에서도 유지되고 다른 책이 섞이지 않으며 페이지 링크에 필터가 이월된다" do
    (PER_PAGE + 1).times { |i| create_report(book: @book, body: "긴긴밤 본문 #{i}") }
    # 미끼: 필터 where 절이 사라지면 최신순으로 섞여 들어와 페이지 결과·카운트를 바꾼다.
    3.times { |i| create_report(book: @other_book, body: "암탉 미끼 본문 #{i}") }

    login_as @student

    get reports_path(book_id: @book.id) # 1페이지
    assert_response :success
    assert_select "article.card", PER_PAGE, "1페이지는 긴긴밤 #{PER_PAGE}건만(암탉 미끼 제외)"
    assert_no_match "암탉 미끼 본문", response.body, "필터가 다른 책을 배제한다"

    get reports_path(book_id: @book.id, page: 2) # 2페이지
    assert_response :success
    assert_match "『긴긴밤』 독후감", response.body, "2페이지에도 필터 문맥이 유지된다"
    assert_select "article.card", 1, "긴긴밤 21건 중 2페이지에는 1건만(암탉 3건이 섞이면 4건이 됨)"
    assert_no_match "암탉 미끼 본문", response.body, "2페이지에도 다른 책이 섞이지 않는다"
    assert_select "a[href*='book_id=']", true, "페이지 이동 링크에 book_id 필터가 이월된다"
  end

  private

  PER_PAGE = ReportsController::PER_PAGE

  def create_report(book: nil, book_title: nil, body: "본문입니다.", reviewed: false)
    Report.create!(
      user: @student, classroom: @classroom,
      book: book, book_title: book_title, body: body, reviewed: reviewed
    )
  end
end
