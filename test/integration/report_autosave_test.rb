require "test_helper"

# 독후감 자동 저장(2026-09-12 되살림 — docs/improve/베타피드백_통합정리.md §5-1, WR-1).
#
# 브라우저의 report-autosave 컨트롤러는 임시 저장과 같은 save_draft 경로를 JSON 으로 부른다.
# 여기서는 그 서버 계약과, 자동 저장이 생기면서 깨질 뻔한 제출 판정을 고정한다.
# · 첫 저장은 초안을 만들고 다음 저장이 갱신할 주소를 돌려준다(제출·AI 첨삭은 안 탄다).
# · 이미 제출한 글은 자동 저장이 덮어쓰지 못한다(다른 탭에서 방금 낸 글).
# · **고쳐쓰기**: 자동 저장이 본문을 먼저 저장해 두면 '수정하기' 요청에는 본문 변경이 없다.
#   "이번 요청에서 본문이 바뀌었나"로 판정하던 시절 그대로면 고쳐 쓴 글이 선생님께 영영 안 간다.
class ReportAutosaveTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  JSON_HEADERS = { "Accept" => "application/json" }.freeze

  setup do
    @school = School.create!(name: "자동저장학교")
    @classroom = Classroom.create!(school: @school, grade: 3, class_no: 1)
    @teacher = User.create!(school: @school, classroom: @classroom, name: "자동저장담임", role: :teacher, password: "password")
    @classroom.update!(teacher: @teacher)
    @student = User.create!(school: @school, classroom: @classroom, name: "자동저장학생", password: "password",
                            ai_consent: true, privacy_consent_at: Time.current)
    @book = Book.create!(title: "마틸다", author: "로알드 달", category: :recommended)
  end

  # --- 저장 계약 ---

  test "첫 자동 저장은 제출 없이 초안을 만들고 이어서 갱신할 주소를 돌려준다" do
    login_as @student

    assert_no_enqueued_jobs only: AiReviewJob do
      assert_difference -> { Report.count }, 1 do
        post reports_path, params: { save_draft: "1", report: { book_id: @book.id, book_title: @book.title, body: "쓰기 시작한 글" } },
                           headers: JSON_HEADERS
      end
    end

    assert_response :created
    draft = Report.order(:created_at).last
    assert draft.draft?, "자동 저장은 제출이 아니다(submitted_at 미기록)"

    json = response.parsed_body
    assert_equal draft.id, json["id"]
    assert_equal report_path(draft), json["update_url"]
    assert_equal edit_report_path(draft), json["edit_url"]
    assert_equal @book.id, json["book_id"], "원격 검색 책이면 여기서 등록된 id 를 폼에 심는다"
  end

  test "다음 자동 저장은 같은 초안의 본문만 바꾸고 제출하지 않는다" do
    draft = keyboard_draft
    login_as @student

    assert_no_enqueued_jobs only: AiReviewJob do
      patch report_path(draft), params: { save_draft: "1", report: { body: "더 쓴 글" } }, headers: JSON_HEADERS
    end

    assert_response :success
    assert_equal edit_report_path(draft), response.parsed_body["edit_url"]
    draft.reload
    assert_equal "더 쓴 글", draft.body
    assert draft.draft?
  end

  test "본문이 비면 자동 저장은 422 로 거절한다(빈 '작성 중' 글을 만들지 않는다)" do
    login_as @student

    assert_no_difference -> { Report.count } do
      post reports_path, params: { save_draft: "1", report: { book_title: "빈책", body: "" } }, headers: JSON_HEADERS
    end
    assert_response :unprocessable_entity
    assert response.parsed_body["errors"].present?
  end

  # 다른 탭에서 방금 제출한 글을 남은 탭의 자동 저장이 덮어쓰면, 교사가 보는 본문과 AI 첨삭
  # 대상이 어긋난다. 제출된 글의 본문은 제출 경로로만 바뀐다.
  test "이미 제출한 글은 자동 저장이 덮어쓰지 못한다" do
    submitted = Report.create!(user: @student, classroom: @classroom, book_title: "낸 책",
                               body: "제출한 본문", ai_status: :pending, submitted_at: Time.current)
    login_as @student

    patch report_path(submitted), params: { save_draft: "1", report: { body: "남은 탭의 옛 글" } }, headers: JSON_HEADERS
    assert_response :conflict
    assert_equal "제출한 본문", submitted.reload.body

    # 임시 저장 버튼(HTML)으로 와도 같다.
    patch report_path(submitted), params: { save_draft: "1", report: { body: "남은 탭의 옛 글" } }
    assert_redirected_to report_path(submitted)
    assert_equal "제출한 본문", submitted.reload.body
  end

  test "담임은 학생의 초안을 임시·자동 저장할 수 없다(작성자 본인만)" do
    draft = keyboard_draft
    login_as @teacher

    patch report_path(draft), params: { save_draft: "1", report: { body: "담임이 바꾼 글" } }, headers: JSON_HEADERS
    assert_response :forbidden
    assert_equal "쓰다 만 글이에요.", draft.reload.body
  end

  # --- 제출 판정 ---

  test "자동 저장된 새 초안을 내면 '고쳐 썼어요'가 아니라 제출 안내가 나오고 첨삭이 시작된다" do
    draft = keyboard_draft
    login_as @student

    assert_enqueued_with job: AiReviewJob do
      patch report_path(draft), params: { report: { body: "다 쓰고 조금 더 고친 글이에요." } }
    end
    assert draft.reload.submitted?
    assert_equal "독후감을 제출했어요. 선생님이 확인한 뒤 첨삭 결과를 볼 수 있어요.", flash[:notice]
  end

  test "고쳐쓰기: 자동 저장이 본문을 먼저 저장해 두어도 '수정하기'를 누르면 선생님께 다시 간다" do
    revision = start_revision
    login_as @student

    # 자동 저장 — 고친 본문이 이미 저장된다.
    patch report_path(revision), params: { save_draft: "1", report: { body: "책 속 장면을 더해 고친 글이에요." } },
                                 headers: JSON_HEADERS
    assert revision.reload.draft?

    # '수정하기' — 이번 요청의 본문은 저장된 것과 같다(바뀐 것이 없다).
    assert_enqueued_with job: AiReviewJob do
      patch report_path(revision), params: { report: { body: "책 속 장면을 더해 고친 글이에요." } }
    end
    assert revision.reload.submitted?, "원본에서 실제로 고친 글이면 요청에 본문 변경이 없어도 제출된다"
    assert_equal "고쳐 썼어요! 선생님이 다시 확인해요.", flash[:notice]
  end

  test "고쳐쓰기: 원본과 같은 본문이면 제출해도 재첨삭하지 않는다(줄바꿈·앞뒤 공백 차이 무시)" do
    revision = start_revision
    login_as @student

    assert_no_enqueued_jobs only: AiReviewJob do
      patch report_path(revision), params: { report: { body: "  #{revision.body.gsub("\n", "\r\n")}\r\n" } }
    end
    assert revision.reload.draft?, "고친 곳이 없으면 선생님께 보내지 않는다(동일 본문 AI 재호출 낭비 방지 유지)"
  end

  # --- 화면 ---

  test "키보드 초안 편집 화면은 자동 저장을 켜고 저장 상태 자리를 둔다" do
    draft = keyboard_draft
    login_as @student

    get edit_report_path(draft)
    assert_response :success
    assert_select "form[data-controller~='report-autosave'][data-report-autosave-enabled-value='true']"
    assert_select "[data-report-autosave-target='status']", 1
    assert_select "input[name='save_draft']", 1
    assert_select "meta[name='turbo-cache-control'][content='no-cache']", 1,
                  "뒤로 가기가 옛 스냅샷을 되살려 저장된 초안을 덮지 않게 스냅샷을 남기지 않는다"
  end

  test "고쳐쓰기 편집 화면은 원본 본문을 '수정하기' 판정 기준으로 넘긴다" do
    revision = start_revision
    login_as @student

    get edit_report_path(revision)
    assert_response :success
    assert_select "form[data-controller~='report-edit'][data-controller~='report-autosave']" do |forms|
      # 줄바꿈이 든 값이라 CSS 선택자 대신 속성값을 직접 비교한다.
      assert_equal revision.revision_of.body, forms.first["data-report-edit-baseline-value"]
    end
    assert_select "form[data-report-autosave-submit-label-value='수정하기']"
  end

  # 사진 초안의 첫 제출 화면은 "제출하기를 눌러야 첨삭이 시작돼요"를 못박고 있다. '저장했어요'가
  # '다 됐다'로 읽히지 않게 자동 저장은 끄고, 쓴 게 있으면 떠날 때 경고만 한다.
  test "사진 초안의 첫 제출 화면은 자동 저장을 끄고 경고만 한다" do
    draft = Report.create!(user: @student, classroom: @classroom, book_title: "사진 책",
                           input_mode: :ocr, body: "사진에서 읽어낸 본문이에요.", ai_status: :done)
    login_as @student

    get edit_report_path(draft)
    assert_response :success
    assert_select "form[data-controller~='report-autosave'][data-report-autosave-enabled-value='false']"
    assert_select "[data-report-autosave-target='status']", 0
    assert_select "input[name='save_draft']", 0
  end

  test "질문형 작성 화면은 답을 본문으로 옮기며 자동 저장한다" do
    login_as @student

    get new_report_path(input_mode: :keyboard, guided: 1, report: { book_id: @book.id, book_title: @book.title })
    assert_response :success
    assert_select "[data-controller='report-guide'][data-action~='report-autosave:created->report-guide#draftCreated']"
    assert_select "textarea[data-report-guide-target='answer'][data-action='input->report-guide#sync']"
    assert_select "form[data-controller~='report-autosave'][data-report-autosave-enabled-value='true']"
  end

  private

  def keyboard_draft
    Report.create!(user: @student, classroom: @classroom, book: @book, book_title: @book.title,
                   body: "쓰다 만 글이에요.", input_mode: :keyboard, ai_status: :pending)
  end

  # 승인된 원본에서 고쳐쓰기를 시작한 상태(revise 가 만든 초안).
  def start_revision
    original = Report.create!(user: @student, classroom: @classroom, book: @book, book_title: @book.title,
                              body: "처음 쓴 글이에요.\n마틸다가 좋았어요.", ai_status: :done,
                              submitted_at: 2.days.ago, reviewed: true, reviewed_at: 1.day.ago,
                              rubric: { content: 3, emotion: 3, life: 2, structure: 3, spelling: 4 }, avg: 3.0, level: "B")
    login_as @student
    post revise_report_path(original)
    revision = @student.reports.where(revision_of: original).last
    delete session_path
    revision
  end
end
