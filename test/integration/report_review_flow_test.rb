require "test_helper"

# Phase 3 완료 게이트 핵심 플로우(헤드리스, 오프라인):
# 학생 작성 → AI 첨삭(규칙기반) → 교사 승인 → reviewed + 포인트 반영.
class ReportReviewFlowTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @school = School.create!(name: "플로우학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @teacher = User.create!(school: @school, classroom: @classroom, name: "플로우담임", role: :teacher, password: "password")
    @classroom.update!(teacher: @teacher)
    @student = User.create!(school: @school, classroom: @classroom, name: "플로우학생", password: "password")
  end

  test "student writes, AI reviews offline, teacher approves, points increase" do
    points_before = @student.points
    experience_before = @student.experience

    # 1) 학생: 로그인 + 작성 + 첨삭 잡 실행(규칙기반, 네트워크 없음)
    login_as @student
    perform_enqueued_jobs do
      post reports_path, params: { report: { book_title: "마당을 나온 암탉",
        body: "나는 이 책을 읽고 우리의 삶과 나의 경험을 떠올리며 감동을 느꼈다. 스스로 반성하고 다짐했다." } }
    end

    report = @student.reports.order(:created_at).last
    assert report.reload.done?, "AI 첨삭이 완료(done)되어야 한다"
    assert_operator @student.reload.points, :>, points_before, "AI 첨삭으로 포인트가 올라야 한다"
    assert_operator @student.experience, :>, experience_before, "AI 첨삭으로 경험치도 올라야 한다"
    assert_equal @student.points - points_before, @student.experience - experience_before,
                 "독후감 보상 포인트와 경험치는 같은 양이어야 한다"

    # 2) 교사: 로그인 + 승인
    delete session_path
    login_as @teacher
    post approve_teacher_review_path(report)

    report.reload
    assert report.reviewed?, "승인 후 reviewed 여야 한다"
    assert_not_nil report.reviewed_at
    assert_operator @student.reload.points, :>, points_before, "전체 플로우 후 학생 포인트가 증가해야 한다"
  end

  # 검색 캐시(searched)로 유입된 도서에 승인 독후감이 붙으면 정식 카탈로그로 승격돼(Book#
  # promote_from_search!) 독서활동 허브·자동완성에서 정상 도서로 취급된다(피그말리온 막다른 길 해소).
  test "teacher approval promotes a searched (search-cache) book into the catalog" do
    searched = Book.create!(title: "검색으로 찾은 무명책", author: "공자장",
                            isbn: "9791112114198", category: :searched)
    report = Report.create!(user: @student, classroom: @classroom, book: searched,
                            book_title: searched.title, body: "본문", ai_status: :done)

    login_as @teacher
    post approve_teacher_review_path(report)

    assert report.reload.reviewed?, "승인되어야 한다"
    assert searched.reload.recommended?, "승인된 검색 캐시 도서는 정식 카탈로그로 승격돼야 한다"
  end

  private
end
