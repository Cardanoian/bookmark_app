require "test_helper"

# 미제출 초안 경계(submitted_at) — 원인 결함의 회귀 가드.
#
# OCR(사진) 경로는 첨부를 붙이려고 학생이 제출하기 **전에** Report 를 영속화하고(OcrController),
# OcrJob 이 판독을 마치면 `ai_status: :done` 을 쓴다. 제출 여부를 그 컬럼으로 추론하던 시절엔
# 미제출 초안이 "첨삭 끝나고 승인만 남은 글"과 구별되지 않아 ① 교사 검토 큐에 올라오고
# ② 승인되면 `reviewed=true` 인데 `rubric` 은 NULL 이라 `feedback_visible?` 이 영구히 false —
# 5축·첨삭·등급·포인트가 통째로 없는 독후감이 확정됐다(운영 재현 사례: 사진 업로드 54초 뒤
# 교사 승인, similarity·rubric·level 전부 NULL = AiReviewJob 이 한 번도 안 돎).
class ReportDraftSubmissionTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @school = School.create!(name: "초안학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @teacher = User.create!(school: @school, classroom: @classroom, name: "초안담임", role: :teacher, password: "password")
    @classroom.update!(teacher: @teacher)
    @student = User.create!(school: @school, classroom: @classroom, name: "초안학생", password: "password",
                            ai_consent: true, privacy_consent_at: Time.current)
  end

  # --- 결함의 핵심: 교사 큐 격리 ---

  test "판독을 마친 미제출 OCR 초안은 교사 검토 큐에도 카운트에도 나타나지 않는다" do
    draft = ocr_draft_after_reading
    submitted = submitted_report

    login_as @teacher
    get teacher_reviews_path
    assert_response :success

    assert_select "#report_#{submitted.id}", 1, "제출된 글은 큐에 있어야 한다"
    assert_select "#report_#{draft.id}", 0, "미제출 초안이 검토 큐에 새면 안 된다"
    assert_select "a[href=?]", teacher_reviews_path(status: "pending"), text: /미검토 1/
  end

  test "미제출 초안은 담임 대시보드 통계·검토 큐 요약에서도 빠진다" do
    ocr_draft_after_reading
    submitted_report

    login_as @teacher
    get teacher_dashboard_path
    assert_response :success

    assert_equal 1, assigns_report_total, "초안은 학급 독후감 수에 잡히지 않는다"
  end

  # --- 결함의 확정 단계: 승인 차단(fail-closed) ---

  test "미제출 초안은 URL 직접 요청으로도 승인되지 않는다" do
    draft = ocr_draft_after_reading
    login_as @teacher

    post approve_teacher_review_path(draft)
    assert_response :forbidden
    assert_not draft.reload.reviewed?, "rubric 없는 초안이 승인되면 5축·첨삭이 영영 없는 글이 확정된다"
  end

  test "미제출 초안은 일괄 승인 대상에도 포함되지 않는다" do
    draft = ocr_draft_after_reading
    submitted = submitted_report
    login_as @teacher

    post batch_approve_teacher_reviews_path, params: { report_ids: [ draft.id, submitted.id ] }

    assert submitted.reload.reviewed?, "제출된 글은 정상 승인된다"
    assert_not draft.reload.reviewed?
  end

  # --- 임시 저장(save_draft): 제출하지 않는 저장 ---

  test "임시 저장으로 만든 글은 제출되지 않는다(교사 큐·AI 첨삭 모두 안 탄다)" do
    login_as @student

    assert_no_enqueued_jobs only: AiReviewJob do
      assert_difference -> { Report.count }, 1 do
        post reports_path, params: { save_draft: "임시 저장",
                                     report: { book_title: "임시책", body: "쓰다 만 글" } }
      end
    end

    draft = Report.order(:created_at).last
    assert draft.draft?, "submitted_at 이 기록되면 안 된다"
    assert_redirected_to edit_report_path(draft)
  end

  # 미제출 초안은 rubric 이 비어 있어 first_review? 가 참이다. update 에서 그 분기까지 건너뛰지
  # 않으면 "임시 저장"이 곧 "제출하기"가 되어 첨삭이 돌고 교사 큐에 올라간다 — 가장 놓치기 쉬운 지점.
  test "임시 저장은 update 의 first_review? 승격도 건너뛴다" do
    login_as @student
    post reports_path, params: { save_draft: "1", report: { book_title: "임시책", body: "처음 쓴 글" } }
    draft = Report.order(:created_at).last

    assert_no_enqueued_jobs only: AiReviewJob do
      patch report_path(draft), params: { save_draft: "1", report: { body: "더 쓴 글" } }
    end

    draft.reload
    assert draft.draft?, "임시 저장이 제출로 승격되면 안 된다"
    assert_equal "더 쓴 글", draft.body
  end

  test "임시 저장한 초안을 제출 버튼으로 내면 그때 제출·첨삭이 시작된다" do
    login_as @student
    post reports_path, params: { save_draft: "1", report: { book_title: "임시책", body: "처음 쓴 글" } }
    draft = Report.order(:created_at).last

    assert_enqueued_with job: AiReviewJob do
      patch report_path(draft), params: { report: { body: "다 써서 냅니다" } }
    end
    assert draft.reload.submitted?
  end

  test "본문이 비면 임시 저장으로 빈 초안을 만들지 않는다" do
    login_as @student

    assert_no_difference -> { Report.count } do
      post reports_path, params: { save_draft: "1", report: { book_title: "빈책", body: "" } }
    end
    assert_response :unprocessable_entity
  end

  # 사진 초안 화면은 "제출하기를 눌러야 첨삭이 시작돼요"를 못박고 있다. 옆에 임시 저장이
  # 나란히 뜨면 아이가 저장했다고 믿고 떠나 첨삭이 영영 안 붙는다.
  test "사진(OCR) 초안 편집 화면에는 임시 저장 버튼이 없다" do
    draft = ocr_draft_after_reading
    login_as @student

    get edit_report_path(draft)
    assert_response :success
    assert_select "input[name='save_draft']", count: 0
  end

  # --- 학생 화면: 초안을 초안이라고 말하기 ---

  # 사진 초안은 학생이 "저장"한 것이 아니라 업로드 순간 서버가 만든 레코드다(판독 결과를 받을
  # 자리). 학생이 직접 임시 저장한 키보드 초안과 같은 "작성 중"으로 뭉개면, 아이는 자기가
  # 저장해 둔 줄 알고 제출하기를 누르지 않는다 — 첨삭이 영영 안 붙던 사고의 학생 쪽 절반이다.
  test "학생 화면은 사진 초안을 '작성 중'이 아니라 '제출 전 확인'으로 구분하고 제출 CTA 를 준다" do
    draft = ocr_draft_after_reading
    login_as @student

    get report_path(draft)
    assert_response :success
    assert_match "제출 전 확인", response.body
    assert_no_match(/작성 중/, response.body, "사진 초안은 키보드 초안과 구분한다")
    assert_match "아직 제출하지 않았어요", response.body
    assert_no_match "선생님이 확인하고 있어요", response.body
    assert_no_match "선생님 확인 중", response.body
    assert_select "a[href=?]", edit_report_path(draft), text: "이어서 쓰고 제출하기"
  end

  test "판독 중인 사진 초안은 '사진 읽는 중'으로 보인다" do
    draft = Report.create!(user: @student, classroom: @classroom, book_title: "사진 책",
                           input_mode: :ocr, ai_status: :processing)
    login_as @student

    get report_path(draft)
    assert_response :success
    assert_match "사진 읽는 중", response.body
  end

  # 학생이 직접 누른 임시 저장은 그대로 "작성 중"이다(사진 초안과 다른 상태).
  test "키보드 초안은 '작성 중'으로 보인다" do
    draft = Report.create!(user: @student, classroom: @classroom, book_title: "직접 쓴 책",
                           body: "쓰다 만 글이에요.", input_mode: :keyboard, ai_status: :pending)
    login_as @student

    get report_path(draft)
    assert_response :success
    assert_match "작성 중", response.body
  end

  test "compose 화면은 판독이 끝나면 '읽고 있어요'가 아니라 제출 안내를 보여준다" do
    draft = ocr_draft_after_reading
    login_as @student

    get edit_report_path(draft)
    assert_response :success
    assert_no_match "사진에서 글자를 읽고 있어요", response.body
    assert_match "사진을 다 읽었어요", response.body
    assert_match "제출하기", response.body
  end

  # --- 제출하면 실제로 5축이 붙는가(원 증상의 반대 방향) ---

  test "OCR 초안을 그대로 제출하면 submitted_at 이 찍히고 5축 첨삭이 실제로 저장된다" do
    draft = ocr_draft_after_reading
    login_as @student

    perform_enqueued_jobs do
      patch report_path(draft), params: { report: { body: draft.body } }
    end

    draft.reload
    assert draft.submitted?, "제출하기를 누르면 제출 사실이 기록된다"
    assert draft.done?
    assert draft.rubric.present?, "제출 후에는 5축 루브릭이 있어야 한다"
    ReadingDomain::RUBRIC_AXES.each { |axis| assert draft.rubric_data[axis].present?, "#{axis} 축 점수가 있어야 한다" }
    assert_includes %w[A B C], draft.level
    assert_not_nil draft.avg

    delete session_path
    login_as @teacher
    get teacher_reviews_path
    assert_select "#report_#{draft.id}", 1, "제출한 뒤에는 교사 큐에 나타난다"
  end

  test "재제출은 최초 제출 시각을 덮어쓰지 않는다" do
    report = submitted_report(submitted_at: 3.days.ago)
    original = report.submitted_at
    login_as @student

    patch report_path(report), params: { report: { body: "고쳐서 다시 낸 본문이에요." } }

    assert_equal original.to_i, report.reload.submitted_at.to_i
  end

  # --- 같은 계열: 고쳐쓰기 초안도 편집 전에는 제출본이 아니다 ---

  test "고쳐쓰기 초안은 학생이 고쳐 내기 전까지 교사 큐에 뜨지 않는다" do
    original = submitted_report(reviewed: true, reviewed_at: Time.current,
                                rubric: rubric_hash, avg: 4.5, level: "A")
    login_as @student
    post revise_report_path(original)
    revision = @student.reports.where.not(id: original.id).order(:created_at).last
    assert revision.draft?, "revise 초안은 부모의 rubric·done 을 물려받지만 아직 제출본이 아니다"

    delete session_path
    login_as @teacher
    get teacher_reviews_path
    assert_select "#report_#{revision.id}", 0

    delete session_path
    login_as @student
    patch report_path(revision), params: { report: { body: "실제로 고쳐 쓴 본문이에요." } }
    assert revision.reload.submitted?

    delete session_path
    login_as @teacher
    get teacher_reviews_path
    assert_select "#report_#{revision.id}", 1
  end

  private

  # OcrController#create 가 만든 초안 + OcrJob 이 판독을 마친 뒤의 상태(제출 전).
  # 결함의 무대가 정확히 이 상태다 — 본문도 있고 ai_status 도 done 인데 아직 낸 글이 아니다.
  def ocr_draft_after_reading
    Report.create!(user: @student, classroom: @classroom, book_title: "사진 책",
                   input_mode: :ocr, body: "사진에서 읽어낸 본문이에요.", ai_status: :done)
  end

  def submitted_report(**attrs)
    Report.create!({ user: @student, classroom: @classroom, book_title: "제출한 책",
                     body: "직접 써서 제출한 본문이에요.", ai_status: :done,
                     submitted_at: Time.current }.merge(attrs))
  end

  def rubric_hash
    { content: 5, emotion: 5, life: 5, structure: 4, spelling: 4 }
  end

  # 대시보드는 집계값을 화면에만 노출하므로 렌더된 총 독후감 수를 읽는다.
  def assigns_report_total
    @controller.view_assigns["total_reports"]
  end
end
