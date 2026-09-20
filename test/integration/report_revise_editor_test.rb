require "test_helper"

# 고쳐쓰기 편집 화면의 참고 패널(이전 글 + 선생님이 승인한 조언). 학생이 고치는 **동안** 이전 글과
# 조언을 보게 하되, 조언은 원본이 교사 승인(feedback_visible?)된 경우에만 **렌더**한다 —
# 승인 전 첨삭 문구·점수·등급이 응답 본문에 실리면 안 된다(report_feedback_gate_test 와 같은 계약).
class ReportReviseEditorTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "고쳐쓰기학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @teacher = User.create!(school: @school, classroom: @classroom, name: "고쳐쓰기담임", role: :teacher, password: "password")
    @classroom.update!(teacher: @teacher)
    @student = User.create!(school: @school, classroom: @classroom, name: "고쳐쓰기학생", password: "password")
  end

  test "승인된 원본을 고쳐 쓰면 편집 화면에 이전 글과 교사 편집본 조언이 함께 보인다" do
    original = submitted_report(
      reviewed: true, reviewed_at: Time.current, teacher_comment: "주인공 마음을 더 써 보자",
      teacher_feedback: { praise: [ "교사가 다듬은 칭찬" ], fix: [ "교사가 다듬은 보완" ],
                           grow: [ { text: "교사가 다듬은 성장", standard_code: "6국05-04" } ] }
    )

    login_as @student
    revision = start_revision(original)
    get edit_report_path(revision)
    assert_response :success

    assert_select "[data-role=revision-reference]", count: 2 # 모바일 <details> + 데스크톱 <aside>
    assert_select "details[data-role=revision-reference] summary", text: /이전 글과 선생님 조언 보기/
    assert_match "이전 글", response.body
    assert_match "처음 쓴 독후감 본문이에요.", response.body
    # 교사 편집본(teacher_feedback)이 AI 원본보다 우선한다(_report_feedback 의 student_feedback 규칙).
    assert_match "교사가 다듬은 칭찬", response.body
    assert_match "교사가 다듬은 보완", response.body
    assert_match "교사가 다듬은 성장", response.body
    assert_no_match "AI 원본 칭찬", response.body
    assert_match "주인공 마음을 더 써 보자", response.body
    assert_match "선생님의 5축 첨삭", response.body
    assert_no_match "선생님이 이전 글을 확인하기 전이에요", response.body

    # 참고 패널을 두 번 렌더해도 편집 화면의 DOM id 가 겹치지 않는다(자동 저장·OCR 방송 대상 보호).
    ids = css_select("[id]").map { |node| node["id"] }
    assert_equal ids.uniq, ids, "중복 DOM id: #{ids.tally.select { |_, n| n > 1 }.keys.inspect}"
    assert_select "textarea#report_body_field", count: 1
    assert_select "form[data-controller~=report-autosave]", count: 1
  end

  test "원본이 아직 승인 전이면 이전 글만 보이고 조언 문구·점수·등급은 응답 본문에 없다" do
    original = submitted_report(reviewed: false)

    login_as @student
    revision = start_revision(original)
    get edit_report_path(revision)
    assert_response :success

    assert_select "[data-role=revision-reference]", count: 2
    assert_select "details[data-role=revision-reference] summary", text: /이전 글 보기/
    assert_match "처음 쓴 독후감 본문이에요.", response.body
    assert_match "선생님이 이전 글을 확인하기 전이에요", response.body

    assert_no_match "선생님의 5축 첨삭", response.body
    assert_no_match "잘한 점", response.body
    assert_no_match "보완할 점", response.body
    assert_no_match "성장 제안", response.body
    assert_no_match "AI 원본 칭찬", response.body
    assert_no_match "AI 원본 보완", response.body
    assert_no_match "AI 원본 성장", response.body
    assert_no_match "중간 검사 · 맞춤법", response.body
    assert_no_match %r{\d/5}, response.body
    assert_select ".progress-bar", count: 0
    assert_select "span.rounded-full.font-bold", count: 0
  end

  test "고쳐쓰기가 아닌 글의 편집 화면에는 참고 패널이 없다" do
    draft = Report.create!(user: @student, classroom: @classroom, book_title: "그냥 쓰는 책",
      body: "아직 내지 않은 초안이에요.", ai_status: :pending)

    login_as @student
    get edit_report_path(draft)
    assert_response :success

    assert_select "h1.page-title", text: /독후감 수정/
    assert_select "[data-role=revision-reference]", count: 0
    assert_no_match "이전 글", response.body
    assert_select "textarea#report_body_field", count: 1
  end

  private

  def submitted_report(**attrs)
    Report.create!(
      { user: @student, classroom: @classroom, book_title: "고쳐 쓸 책",
        body: "처음 쓴 독후감 본문이에요.", ai_status: :done, avg: 3.0, level: "B",
        rubric: { content: 3, emotion: 4, life: 2, structure: 3, spelling: 4,
                  praise: [ "AI 원본 칭찬" ], fix: [ "AI 원본 보완" ],
                  grow: [ { text: "AI 원본 성장", standard_code: "6국05-04" } ] },
        submitted_at: Time.current, review_version: 1, completed_review_version: 1 }.merge(attrs)
    )
  end

  # 실제 동선(상세의 '고쳐쓰기' → ReportsController#revise → edit 로 리다이렉트)으로 초안을 만든다.
  def start_revision(original)
    post revise_report_path(original)
    revision = @student.reports.find_by!(revision_of: original)
    assert_redirected_to edit_report_path(revision)
    revision
  end
end
