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

  test "growth has an empty state before an approved scored report exists" do
    get growth_path

    assert_response :success
    assert_match "선생님이 확인한 독후감", response.body
  end

  private

  def create_report(**attrs)
    Report.create!({ user: @student, classroom: @classroom, ai_status: :done }.merge(attrs))
  end

  def scores(value)
    ReadingDomain::RUBRIC_AXES.index_with { value }
  end
end
