require "test_helper"

# 안내형 독후감 작성(guided compose, §1a) — worker-1 의 @guided(ReadingDomain.guided_questions)
# 계약을 소비하는 뷰(_guided_compose)를 검증한다. ReportsController#new 가 항상
# @guided = ReadingDomain.guided_questions(ReadingDomain.guided_band_for(Current.user.classroom&.grade))
# 를 세팅한다는 계약(team-exec-spec.md)을 전제로 한다. worker-1 이 아직 이 배선을 끝내지 않았다면
# @guided 가 nil 이라 new.html.erb 의 가드(`@guided && @guided[:questions].present?`)가 false 로
# 낙하해 일반 폼이 렌더되고, 문항 수를 세는 테스트들은 실패한다(별도 확인 필요 — 최종 보고 참고).
class ReportsGuidedWriteTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @school = School.create!(name: "안내형작성학교")
    @book = Book.create!(title: "긴긴밤", author: "루리", publisher: "문학동네", category: :recommended)
  end

  test "guided compose 화면은 컨트롤러 마운트·초안 만들기·질문 없이 바로 쓰기 링크를 렌더한다" do
    login_as student_in_grade(5)

    get new_report_path(input_mode: :keyboard, guided: 1, report: { book_id: @book.id })
    assert_response :success
    assert_select "div[data-controller='report-guide']", 1
    assert_match "초안 만들기", response.body
    assert_match "질문 없이 바로 쓰기", response.body
  end

  test "g56(5~6학년) 학급 학생은 질문 8개를 받는다" do
    login_as student_in_grade(6)

    get new_report_path(input_mode: :keyboard, guided: 1, report: { book_id: @book.id })
    assert_response :success
    assert_select "textarea[data-report-guide-target='answer']", count: 8
  end

  test "g34(3~4학년) 학급 학생은 질문 7개를 받는다" do
    login_as student_in_grade(3)

    get new_report_path(input_mode: :keyboard, guided: 1, report: { book_id: @book.id })
    assert_response :success
    assert_select "textarea[data-report-guide-target='answer']", count: 7
  end

  test "g12(1~2학년) 학급 학생은 질문 5개를 받는다" do
    login_as student_in_grade(1)

    get new_report_path(input_mode: :keyboard, guided: 1, report: { book_id: @book.id })
    assert_response :success
    assert_select "textarea[data-report-guide-target='answer']", count: 5
  end

  test "학급/학년이 없는(미상) 학생은 age-safety 로 g12 5문항으로 폴백한다" do
    student = User.create!(school: @school, name: "무학급학생", password: "password")
    login_as student

    get new_report_path(input_mode: :keyboard, guided: 1, report: { book_id: @book.id })
    assert_response :success
    assert_select "textarea[data-report-guide-target='answer']", count: 5
  end

  test "ratio_hint 안내와 문항별 example(placeholder) 을 렌더한다" do
    login_as student_in_grade(5)

    get new_report_path(input_mode: :keyboard, guided: 1, report: { book_id: @book.id })
    assert_response :success

    placeholders = css_select("textarea[data-report-guide-target='answer']").map { |node| node["placeholder"] }
    assert placeholders.present?, "질문 카드가 렌더돼야 한다"
    assert placeholders.all?(&:present?), "각 질문 textarea 는 example 을 placeholder 로 가져야 한다"
  end

  # 조립(assemble)은 클라이언트에서만 일어난다 — 서버 create 액션·파라미터 계약은 기존과 동일해야
  # 하므로, 클라이언트가 이미 조립해 보낸 것과 동등한 본문을 직접 post 해 회귀를 검증한다.
  test "조립된 본문의 제출 경로는 기존 create 와 동일하게 동작한다" do
    student = student_in_grade(5)
    login_as student

    assert_enqueued_with(job: AiReviewJob) do
      post reports_path, params: { report: {
        book_id: @book.id, body: "서론\n\n본론\n\n결론", input_mode: "keyboard"
      } }
    end

    report = student.reports.order(:created_at).last
    assert_not_nil report
    assert_equal "서론\n\n본론\n\n결론", report.body
    assert_redirected_to report_path(report)
  end

  # 안전판 회귀 잠금(프런트 리뷰 HIGH·테스트 리뷰 (d)): 조립된 본문을 제출했는데 검증 실패로
  # 재렌더될 때, _form 의 hidden input_mode 덕분에 new.html.erb 가 _book_chooser/_guided_compose 로
  # 새지 않고 편집 폼(#report_body_field)에 초안을 그대로 유지해야 한다(아이가 다시 안 써도 되게).
  test "조립 초안 제출이 검증 실패로 재렌더돼도 본문이 편집 폼에 보존된다" do
    student = student_in_grade(5)
    login_as student

    draft = "저는 동물을 좋아해서 읽었어요.\n\n주인공이 도와주는 장면이 기억에 남아요.\n\n배려를 배웠어요."
    # book_id·book_title 를 비워 book_reference_present 검증을 실패시킨다.
    post reports_path, params: { report: {
      book_id: "", book_title: "", body: draft, input_mode: "keyboard"
    } }

    assert_response :unprocessable_entity
    assert_select "textarea#report_body_field" do |els|
      assert_includes els.first.text, "주인공이 도와주는 장면이 기억에 남아요.",
        "조립한 본문이 편집 폼에 그대로 남아야 한다(초안 유실 금지)"
    end
    assert_select "div[data-controller='report-guide']", 0, "재렌더는 질문 단계로 되돌아가지 않는다"
  end

  private

  def student_in_grade(grade)
    classroom = Classroom.create!(school: @school, grade: grade, class_no: 1)
    teacher = User.create!(school: @school, classroom: classroom, name: "담임#{grade}", role: :teacher, password: "password")
    classroom.update!(teacher: teacher)
    User.create!(school: @school, classroom: classroom, name: "학생#{grade}", password: "password")
  end
end
