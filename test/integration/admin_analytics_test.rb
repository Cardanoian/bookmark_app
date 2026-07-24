require "test_helper"

# P7.5 전교 통합 통계 + CSV: 전 학교 집계 렌더 + 학교별 원자료 CSV 내보내기.
class AdminAnalyticsTest < ActionDispatch::IntegrationTest
  setup do
    @superadmin = User.create!(name: "총괄", role: :superadmin, password: "password")

    @school_a = School.create!(name: "가나다초")
    @class_a = Classroom.create!(school: @school_a, grade: 5, class_no: 1)
    @student_a = User.create!(school: @school_a, classroom: @class_a, name: "가학생", role: :student, password: "password", points: 50)
    Report.create!(user: @student_a, classroom: @class_a, book_title: "가책", body: "본문",
                   rubric: { content: 4, emotion: 4, life: 5, structure: 3, spelling: 4 }, avg: 4.0, level: "A", reviewed: true)

    @school_b = School.create!(name: "라마바초")
    @class_b = Classroom.create!(school: @school_b, grade: 6, class_no: 1)
    @student_b = User.create!(school: @school_b, classroom: @class_b, name: "라학생", role: :student, password: "password", points: 30)

    login_as @superadmin
  end

  test "show renders global aggregates across all schools" do
    get admin_root_path
    assert_response :success
    assert_match "가나다초", response.body
    assert_match "라마바초", response.body
    assert_match "50XP", response.body
  end

  test "export returns text/csv with a per-school row" do
    get admin_analytics_export_path(format: :csv)
    assert_response :success
    assert_match "text/csv", response.media_type
    assert_match "가나다초", response.body
    assert_match "라마바초", response.body
    # 헤더 행 존재.
    assert_match "학교", response.body
  end

  private
end
