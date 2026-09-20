require "test_helper"

class GrowthsTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "성장학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @student = User.create!(school: @school, classroom: @classroom, name: "성장학생", password: "password")
    login_as @student
  end

  test "growth shows only the student's approved scored reports in time order" do
    older = create_report(
      book_title: "첫 책",
      rubric: scores(2),
      reviewed: true,
      created_at: 2.days.ago
    )
    newer = create_report(
      book_title: "둘째 책",
      rubric: scores(3),
      teacher_rubric: { content: 5 },
      reviewed: true,
      created_at: 1.day.ago
    )
    create_report(book_title: "승인 전 책", rubric: scores(5), reviewed: false)
    other = User.create!(school: @school, classroom: @classroom, name: "다른학생", password: "password")
    Report.create!(user: other, classroom: @classroom, book_title: "다른 학생 책", rubric: scores(5), reviewed: true)

    get growth_path

    assert_response :success
    assert_match older.book_title, response.body
    assert_match newer.book_title, response.body
    assert_no_match "승인 전 책", response.body
    assert_no_match "다른 학생 책", response.body
    assert_match "내용 이해 영역이 가장 많이 성장", response.body
    assert_select "a[href=?]", report_path(older)
    assert_select "a[href=?]", report_path(newer)
  end

  test "growth renders the radar chart, axis bars and change bars" do
    create_report(book_title: "첫 책", rubric: scores(2), reviewed: true, created_at: 2.days.ago)
    create_report(book_title: "둘째 책", rubric: scores(4), reviewed: true, created_at: 1.day.ago)

    get growth_path

    assert_response :success
    # 방사형(오각형) 차트 — 데이터 폴리곤 + 지난 글 비교 점선 폴리곤
    assert_select "svg.radar-chart-svg" do
      assert_select "polygon[stroke-dasharray]", 1
    end
    # 축별 막대 + 시간 변화 막대(승인 글 수만큼)
    assert_select ".progress-bar", ReadingDomain::RUBRIC_AXES.size + 2
    assert_select ".progress-bar__fill"
    assert_match "시간에 따른 변화", response.body
  end

  test "growth omits the comparison polygon when only one report exists" do
    create_report(book_title: "첫 책", rubric: scores(3), reviewed: true, created_at: 1.day.ago)

    get growth_path

    assert_response :success
    assert_select "svg.radar-chart-svg"
    assert_select "polygon[stroke-dasharray]", 0
  end

  # 자동 저장(2026-09-12)은 첫 저장에서 초안 행을 만든다 — created_at 은 "쓰기 시작한 시각"이다.
  # 시계열은 **낸 순서**다: 먼저 쓰기 시작했어도 나중에 낸 글이 '최근 글'이고, 날짜도 낸 날로 보인다.
  test "growth orders reports by submission time, not by when writing started" do
    started_first = create_report(book_title: "먼저 시작해 나중에 낸 책", rubric: scores(4), reviewed: true,
                                  created_at: 5.days.ago, submitted_at: 1.day.ago)
    create_report(book_title: "나중에 시작해 먼저 낸 책", rubric: scores(2), reviewed: true,
                  created_at: 3.days.ago, submitted_at: 2.days.ago)

    get growth_path

    assert_response :success
    assert_match "최근 「#{started_first.book_title}」", response.body
    assert_match "가장 많이 성장", response.body, "2점 → 4점: 나중에 낸 글이 최근 글이라 성장으로 읽힌다"
    assert_match 1.day.ago.strftime("%-m월 %-d일"), response.body, "마지막 기록은 낸 날"
    assert_no_match 5.days.ago.strftime("%-m월 %-d일"), response.body, "쓰기 시작한 날은 보이지 않는다"
  end

  test "growth has an empty state before an approved scored report exists" do
    get growth_path

    assert_response :success
    assert_match "선생님이 확인한 독후감", response.body
  end

  private

  # 제출했고 지금 제출의 첨삭까지 끝난 글(성장 화면은 교사가 그 첨삭을 승인한 글만 쓴다 — Report.approved).
  def create_report(**attrs)
    Report.create!({ user: @student, classroom: @classroom, **review_ready_attributes(submitted_at: nil) }
                     .merge(submitted_at: attrs[:created_at] || Time.current).merge(attrs))
  end

  def scores(value)
    ReadingDomain::RUBRIC_AXES.index_with { value }
  end
end
