require "test_helper"

# 교사 검토 전 AI 첨삭 결과 비공개 게이트(report-review-gate) — 학생 대면 노출 계약의 핵심 회귀.
# 미검토(ai_status done, reviewed false) 독후감은 첨삭 텍스트·등급·향상도·맞춤법 신호를
# 절대 노출하지 않고, 교사 승인(reviewed true) 후에만(그리고 교사 편집본을) 보여준다.
class ReportFeedbackGateTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @school = School.create!(name: "게이트학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @teacher = User.create!(school: @school, classroom: @classroom, name: "게이트담임", role: :teacher, password: "password")
    @classroom.update!(teacher: @teacher)
    @student = User.create!(school: @school, classroom: @classroom, name: "게이트학생", password: "password")
  end

  class RaisingReview
    def call(_report)
      raise "boom"
    end
  end

  test "미승인 독후감은 학생 상세에서 첨삭 텍스트·등급·향상도·맞춤법을 숨긴다" do
    report = unreviewed_report
    login_as @student

    get report_path(report)
    assert_response :success

    assert_no_match "잘한 점", response.body
    assert_no_match "보완할 점", response.body
    assert_no_match "성장 제안", response.body
    assert_no_match "정말 잘 썼어요", response.body
    assert_no_match "다음엔 더 자세히 써 볼까요", response.body
    assert_no_match "표현을 다양하게 써 봐요", response.body
    assert_no_match "중간 검사 · 맞춤법", response.body
    assert_no_match "향상도", response.body
    assert_select "span.rounded-full.font-bold", text: report.level, count: 0

    assert_match "선생님이 확인하고 있어요", response.body
    assert_no_match "첨삭 완료", response.body
    assert_match "선생님 확인 중", response.body
  end

  test "재첨삭 향상도는 승인 전 학생 show 에 노출되지 않는다" do
    original = Report.create!(user: @student, classroom: @classroom, book_title: "책",
      body: "원본 본문", ai_status: :done, avg: 2.0, level: "B",
      rubric: build_reviewed_rubric, reviewed: true, reviewed_at: Time.current)
    revision = Report.create!(user: @student, classroom: @classroom, book_title: "책",
      body: "고쳐 쓴 본문", revision_of: original, prev_avg: original.avg,
      ai_status: :done, avg: 4.5, level: "A", improvement: 2.5,
      rubric: build_reviewed_rubric, reviewed: false)

    login_as @student
    get report_path(revision)
    assert_response :success
    assert_no_match "향상도", response.body
  end

  test "승인 후 학생은 교사 편집본 첨삭·등급·향상도를 본다" do
    original = Report.create!(user: @student, classroom: @classroom, book_title: "책",
      body: "원본 본문", ai_status: :done, avg: 2.0, level: "B",
      rubric: build_reviewed_rubric, reviewed: true, reviewed_at: Time.current)
    revision = Report.create!(user: @student, classroom: @classroom, book_title: "책",
      body: "고쳐 쓴 본문", revision_of: original, prev_avg: original.avg,
      ai_status: :done, avg: 4.5, level: "A", improvement: 2.5,
      rubric: build_reviewed_rubric,
      teacher_feedback: { praise: [ "교사가 다듬은 칭찬" ], fix: [ "교사가 다듬은 보완" ],
                           grow: [ { text: "교사가 다듬은 성장", standard_code: "2국05-01" } ] },
      reviewed: false)

    login_as @teacher
    post approve_teacher_review_path(revision)
    assert revision.reload.reviewed?

    delete session_path
    login_as @student
    get report_path(revision)
    assert_response :success

    assert_match "교사가 다듬은 칭찬", response.body
    assert_match "교사가 다듬은 보완", response.body
    assert_match "교사가 다듬은 성장", response.body
    assert_select "span.rounded-full.font-bold", text: "A"
    assert_match "향상도", response.body
    assert_no_match "선생님이 확인하고 있어요", response.body
    assert_match "확인 완료", response.body
  end

  test "목록에서도 승인 전 등급 배지·선생님 코멘트가 노출되지 않다가 승인 후 노출된다" do
    report = unreviewed_report

    login_as @teacher
    patch teacher_review_path(report), params: { report: { teacher_comment: "코멘트만 저장됨" } }
    report.reload
    assert_not report.reviewed?
    assert_equal "코멘트만 저장됨", report.teacher_comment

    delete session_path
    login_as @student
    get reports_path
    assert_response :success
    assert_select "span.rounded-full.font-bold", text: report.level, count: 0
    assert_no_match "선생님: 코멘트만 저장됨", response.body

    delete session_path
    login_as @teacher
    post approve_teacher_review_path(report)

    delete session_path
    login_as @student
    get reports_path
    assert_response :success
    assert_select "span.rounded-full.font-bold", text: report.level
    assert_match "선생님: 코멘트만 저장됨", response.body
  end

  # 재첨삭 실패는 부모의 rubric 을 상속한 채 ai_status: failed 로 남는다(#misc, revise 관용구).
  # feedback_visible? 은 reviewed? 도 요구하므로 상속된 첨삭이 노출되지 않고, 렌더도 크래시 없어야 한다.
  test "재첨삭 실패 시 상속된 부모 첨삭이 노출되지 않고 크래시 없이 오류 배너를 보여준다" do
    original = Report.create!(user: @student, classroom: @classroom, book_title: "책",
      body: "원본 본문", ai_status: :done, avg: 4.5, level: "A",
      rubric: build_reviewed_rubric, reviewed: true, reviewed_at: Time.current)

    login_as @student
    post revise_report_path(original)
    revision = @student.reports.where.not(id: original.id).order(:created_at).last
    assert revision.done?
    assert revision.rubric.present?, "revise 는 부모 rubric 을 이어받는다"
    assert_not revision.reviewed?

    stub_new(Ai::ReviewService, RaisingReview.new) do
      perform_enqueued_jobs do
        patch report_path(revision), params: { report: { body: "고쳐 쓴 본문으로 바뀜" } }
      end
    end

    revision.reload
    assert revision.failed?
    assert revision.rubric.present?, "부모 rubric 은 잔존해야 한다"
    assert_not revision.reviewed?

    get report_path(revision)
    assert_response :success
    assert_no_match "정말 잘 썼어요", response.body
    assert_match "첨삭에 실패했어요", response.body
  end

  # H1(게이트 우회 차단): 이미 승인된(reviewed=true) 리포트를 학생이 직접 본문 수정·재제출하면
  # 검토 상태가 완전히 리셋된다 — reviewed→false 로 게이트(feedback_visible?)에 재진입하고,
  # 담임 재검토 큐(pending_scope, reviewed:false)로 복귀하며, 옛 본문 대상 교사 편집본은
  # 스테일이라 클리어된다. (수정 전에는 reviewed 가 true 로 유지돼 미검수 새 첨삭이 즉시 노출됐다.)
  test "승인본을 학생이 직접 본문 수정·재제출하면 검토 게이트에 재진입하고 담임 큐로 복귀한다" do
    report = Report.create!(user: @student, classroom: @classroom, book_title: "책",
      body: "원래 승인된 본문", ai_status: :done, avg: 4.5, level: "A",
      rubric: build_reviewed_rubric,
      teacher_feedback: { praise: [ "교사가 다듬은 칭찬" ], fix: [ "교사가 다듬은 보완" ],
                           grow: [ { text: "교사가 다듬은 성장", standard_code: "2국05-01" } ] },
      teacher_rubric: { content: 3, emotion: 3, life: 3, structure: 3, spelling: 3 },
      teacher_comment: "교사가 남긴 코멘트",
      reviewed: true, reviewed_at: Time.current)

    login_as @student
    perform_enqueued_jobs do
      patch report_path(report), params: { report: { body: "학생이 승인 후 직접 고쳐 다시 낸 본문이에요." } }
    end

    report.reload
    # 1. 게이트 재진입: reviewed 가 false 로 리셋되고 재첨삭 잡이 done 으로 완료된다.
    assert_not report.reviewed?, "승인본 직접 재제출은 reviewed 를 false 로 되돌려야 한다"
    assert_nil report.reviewed_at
    assert report.done?, "재첨삭(오프라인 잡) 수행 후 ai_status 는 done"
    # 4. 옛 본문 대상 교사 편집본은 스테일이라 함께 클리어된다(재승인 후 스테일 노출 2차 버그 차단).
    assert_nil report.teacher_feedback, "본문 변경 시 옛 교사 편집본은 클리어된다"
    assert_nil report.teacher_comment
    assert_nil report.teacher_rubric

    # 2. 학생 상세에 새 첨삭·등급 미노출 + "선생님이 확인하고 있어요" 배너.
    get report_path(report)
    assert_response :success
    assert_match "선생님이 확인하고 있어요", response.body
    assert_match "선생님 확인 중", response.body
    assert_no_match "교사가 다듬은 칭찬", response.body
    assert_no_match "교사가 다듬은 보완", response.body
    assert_no_match "교사가 다듬은 성장", response.body
    assert_no_match "향상도", response.body
    assert_select "span.rounded-full.font-bold", count: 0

    # 3. 담임 재검토 큐(pending_scope, reviewed:false)로 복귀한다.
    delete session_path
    login_as @teacher
    get teacher_reviews_path
    assert_response :success
    assert_select "##{ActionView::RecordIdentifier.dom_id(report)}", 1,
      "재제출된 승인본이 담임 검토 큐로 복귀해야 한다"
  end

  private

  def build_reviewed_rubric(praise: [ "정말 잘 썼어요" ], fix: [ "다음엔 더 자세히 써 볼까요" ],
                             grow_text: "표현을 다양하게 써 봐요", standard_code: "2국05-01")
    { content: 5, emotion: 5, life: 5, structure: 5, spelling: 5,
      praise: praise, fix: fix, grow: [ { text: grow_text, standard_code: standard_code } ] }
  end

  def unreviewed_report(**attrs)
    Report.create!(
      { user: @student, classroom: @classroom, book_title: "책",
        body: "본문 내용입니다.", ai_status: :done, avg: 4.5, level: "A",
        rubric: build_reviewed_rubric, reviewed: false }.merge(attrs)
    )
  end

  # Minitest 6 dropped minitest/mock; temporarily swap `.new` on a service class
  # to return an injected double, then restore the inherited Class#new.
  def stub_new(klass, replacement)
    klass.define_singleton_method(:new) { |*, **| replacement }
    yield
  ensure
    klass.singleton_class.send(:remove_method, :new)
  end
end
