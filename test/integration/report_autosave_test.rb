require "test_helper"

# 동시 요청 흉내(2026-09-13 리뷰 #11). 컨트롤러가 행을 잠그기 **직전에** 다른 요청이 먼저 끝났다고 치고
# 행을 바꾼다. 잠근 뒤 다시 읽어 판단하지 않으면 이 변경을 못 보고 그 위에 옛 본문을 쓴다.
# 훅이 없으면 아무 일도 하지 않는다(ActiveStorage variant 시임과 같은 테스트 전용 시임).
module ReportLockRaceHook
  mattr_accessor :before_lock

  def lock!(*)
    ReportLockRaceHook.before_lock&.call(self)
    super
  end
end
Report.prepend(ReportLockRaceHook)

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
    assert_select "[data-controller='report-guide'][data-action~='report-autosave:status->report-guide#showStatus']"
    assert_select "textarea[data-report-guide-target='answer'][data-action='input->report-guide#sync']"
    assert_select "form[data-controller~='report-autosave'][data-report-autosave-enabled-value='true']"
    # "질문 없이 바로 쓰기"는 새 빈 글로 이동하지 않고 이 자리에서 폼을 연다(첫 저장 전에 누르면 초안이 두 편 생겼다).
    assert_select "a[data-report-guide-target='skipLink'][data-action='report-guide#skip']"
  end

  # --- 2026-09-13 리뷰 후속 ---

  # 어제 열어 둔 태블릿 탭에 한 글자만 쳐도, 그사이 집에서 더 쓴 본문이 옛 본문으로 통째로 덮였다.
  test "다른 탭·기기가 더 고친 초안은 옛 화면의 자동 저장이 덮지 못한다" do
    draft = keyboard_draft
    seen_version = draft.draft_version
    travel 1.minute do
      draft.update!(body: "집에서 더 쓴 글이에요.")
    end
    login_as @student

    patch report_path(draft), params: { save_draft: "1", draft_version: seen_version, report: { body: "옛 탭의 한 글자" } },
                              headers: JSON_HEADERS
    assert_response :conflict
    assert_equal "stale", response.parsed_body["error"]
    assert_equal "집에서 더 쓴 글이에요.", draft.reload.body

    # 최신 버전을 들고 오면 저장되고, 다음 저장에 쓸 새 버전을 돌려준다.
    patch report_path(draft), params: { save_draft: "1", draft_version: draft.draft_version, report: { body: "최신 글에 이어 쓴 글" } },
                              headers: JSON_HEADERS
    assert_response :success
    assert_equal "최신 글에 이어 쓴 글", draft.reload.body
    assert_equal draft.draft_version, response.parsed_body["draft_version"]
  end

  # 버전은 마이크로초까지 쓰는 문자열이다. 저장 응답이 준 값과 다시 연 화면이 싣는 값이 한 자리라도
  # 다르면, 새로고침 뒤 첫 자동 저장이 늘 "다른 곳에서 고쳤어요"로 멈춘다.
  test "자동 저장이 돌려준 초안 버전은 다시 연 편집 화면의 버전과 같다" do
    draft = keyboard_draft
    login_as @student

    patch report_path(draft), params: { save_draft: "1", report: { body: "이어 쓴 글" } }, headers: JSON_HEADERS
    returned = response.parsed_body["draft_version"]
    assert_match(/\.\d{6}Z\z/, returned)

    get edit_report_path(draft)
    assert_select "input[type=hidden][name='draft_version'][value=?]", returned
  end

  test "초안 버전을 싣지 않은 자동 저장(예전 화면)은 그대로 받는다" do
    draft = keyboard_draft
    login_as @student

    patch report_path(draft), params: { save_draft: "1", report: { body: "버전 없이 보낸 글" } }, headers: JSON_HEADERS
    assert_response :success
    assert_equal "버전 없이 보낸 글", draft.reload.body
  end

  # 원본을 지우면 revision_of_id 는 nil 이 되지만 rubric 은 남는다. 예전에는 "이미 첨삭 받은 글"로 오인해
  # '수정하기'를 눌러도 선생님께 가지 않았고, 다시 열면 버튼까지 잠겼다.
  test "원본을 지운 고쳐쓰기 초안도 '제출하기'로 선생님께 간다" do
    revision = start_revision
    revision.revision_of.destroy!
    assert_nil revision.reload.revision_of_id
    login_as @student

    get edit_report_path(revision)
    assert_select "form[data-controller~='report-edit']", 0, "원본이 없으니 '고친 곳이 있어야 열리는' 버튼이 아니다"
    assert_select "form[data-report-autosave-enabled-value='true'][data-report-autosave-submit-label-value='제출하기']"
    assert_select "input[type=submit][value='제출하기']"

    patch report_path(revision), params: { save_draft: "1", report: { body: "원본을 지운 뒤 고친 글" } }, headers: JSON_HEADERS
    assert_enqueued_with job: AiReviewJob do
      patch report_path(revision), params: { report: { body: "원본을 지운 뒤 고친 글" } }
    end
    assert revision.reload.submitted?
    assert_equal "독후감을 제출했어요. 선생님이 확인한 뒤 첨삭 결과를 볼 수 있어요.", flash[:notice]
  end

  # 새로고침·뒤로 가기, 앱이 화면을 다시 여는 경우 — 모두 처음 연 새 글 주소로 다시 온다.
  test "새 글 화면에서 자동 저장이 만든 초안은 같은 주소로 다시 오면 이어서 연다" do
    origin = new_report_path(input_mode: :keyboard, report: { book_id: @book.id, book_title: @book.title })
    login_as @student

    post reports_path, params: { save_draft: "1", autosave_origin: origin,
                                 report: { book_id: @book.id, book_title: @book.title, body: "쓰기 시작한 글" } },
                       headers: JSON_HEADERS
    draft = Report.find(response.parsed_body["id"])

    get origin
    assert_redirected_to edit_report_path(draft)
    follow_redirect!
    assert_equal "쓰던 글을 이어서 열었어요.", flash[:notice]

    # 다른 책의 새 글은 새 글이다.
    get new_report_path(input_mode: :keyboard, report: { book_title: "다른 책" })
    assert_response :success

    # 내고 나면 같은 주소도 다시 새 글이다.
    patch report_path(draft), params: { report: { body: "다 쓴 글이에요." } }
    assert draft.reload.submitted?
    get origin
    assert_response :success
  end

  test "오래된 초안·새 글 화면이 아닌 주소는 이어서 열지 않는다" do
    origin = new_report_path(input_mode: :keyboard, report: { book_id: @book.id, book_title: @book.title })
    login_as @student

    post reports_path, params: { save_draft: "1", autosave_origin: "/reports",
                                 report: { book_id: @book.id, book_title: @book.title, body: "주소가 이상한 글" } },
                       headers: JSON_HEADERS
    get origin
    assert_response :success, "새 글 화면 주소가 아니면 기억하지 않는다"

    post reports_path, params: { save_draft: "1", autosave_origin: origin,
                                 report: { book_id: @book.id, book_title: @book.title, body: "어제 쓰다 만 글" } },
                       headers: JSON_HEADERS
    travel ReportsController::AUTOSAVE_ORIGIN_TTL + 1.minute do
      get origin
      assert_response :success, "며칠 뒤 같은 책으로 새 글을 쓰려는 아이를 옛 초안으로 끌고 가지 않는다"
    end
  end

  test "첫 저장 뒤에 원격 검색으로 고른 책도 자동 저장과 제출이 등록한다" do
    draft = Report.create!(user: @student, classroom: @classroom, book_title: "아직 안 고른 책",
                           body: "쓰다 만 글이에요.", input_mode: :keyboard, ai_status: :pending)
    isbn = "9791234567896"
    login_as @student

    with_memory_cache do
      Rails.cache.write("book_meta:#{isbn}", { id: nil, title: "원격으로 고른 책", author: "원격저자",
                                               publisher: "원격출판", isbn: isbn, description: "설명" })

      patch report_path(draft), params: { save_draft: "1", report: { book_id: "", remote_isbn: isbn, book_title: "원격으로 고른 책" } },
                                headers: JSON_HEADERS
    end

    assert_response :success, "본문 칸 없이 책만 바꾼 저장은 저장된 본문을 본다(빈 본문으로 거절하지 않는다)"
    book = Book.find_by!(isbn: isbn)
    assert_equal book.id, draft.reload.book_id
    assert_equal book.id, response.parsed_body["book_id"], "폼이 숨은 book_id 에 심도록 돌려준다"

    # 제출(update)로 와도 등록한다 — 자동 저장 뒤로는 제출이 create 가 아니라 update 다.
    other_isbn = "9791111111112"
    with_memory_cache do
      Rails.cache.write("book_meta:#{other_isbn}", { id: nil, title: "다시 고른 책", author: "저자",
                                                     publisher: "출판", isbn: other_isbn, description: "설명" })
      patch report_path(draft), params: { report: { book_id: "", remote_isbn: other_isbn, book_title: "다시 고른 책", body: "다 쓴 글" } }
    end
    assert_equal Book.find_by!(isbn: other_isbn).id, draft.reload.book_id
    assert draft.submitted?
  end

  # 담임도 "이어서 쓰기"로 학생 초안의 편집 화면에 들어올 수 있다. 서버는 담임의 초안 저장을 막으므로
  # 켜 두면 입력할 때마다 거절당하며 저장 문구만 헛돈다.
  test "담임이 연 학생 초안 편집 화면에는 자동 저장·임시 저장이 없다" do
    draft = keyboard_draft
    login_as @teacher

    get edit_report_path(draft)
    assert_response :success
    assert_select "form[data-controller~='report-autosave'][data-report-autosave-enabled-value='false']"
    assert_select "[data-report-autosave-target='status']", 0
    assert_select "input[name='save_draft']", 0
    assert_select "input[name='draft_version']", 0
  end

  # --- 확인과 갱신 사이의 틈(리뷰 #11) ---

  test "자동 저장이 초안을 읽은 뒤 잠그기 전에 제출이 끝났으면 그 위에 쓰지 않는다" do
    draft = keyboard_draft
    login_as @student

    submitted_meanwhile = ->(report) { Report.where(id: report.id).update_all(body: "방금 낸 글", submitted_at: Time.current) }
    with_write_before_lock(submitted_meanwhile) do
      patch report_path(draft), params: { save_draft: "1", draft_version: draft.draft_version, report: { body: "뒤늦게 닿은 자동 저장" } },
                                headers: JSON_HEADERS
    end

    assert_response :conflict
    assert_equal "already_submitted", response.parsed_body["error"]
    assert_equal "방금 낸 글", draft.reload.body, "선생님께 간 글이 뒤늦은 자동 저장으로 바뀌면 안 된다"
  end

  test "같은 초안의 두 저장이 겹치면 늦게 잠근 쪽은 stale 로 거절된다" do
    draft = keyboard_draft
    seen = draft.draft_version
    login_as @student

    other_tab_saved = ->(report) { Report.where(id: report.id).update_all(body: "다른 탭이 방금 저장한 글", updated_at: 1.second.from_now) }
    with_write_before_lock(other_tab_saved) do
      patch report_path(draft), params: { save_draft: "1", draft_version: seen, report: { body: "같은 버전을 들고 온 저장" } },
                                headers: JSON_HEADERS
    end

    assert_response :conflict
    assert_equal "stale", response.parsed_body["error"]
    assert_equal "다른 탭이 방금 저장한 글", draft.reload.body
  end

  # 본문 저장과 제출 기록이 따로 커밋되던 때는 그 사이에 끼어든 자동 저장이 "아직 초안"을 보고 옛 본문을
  # 썼다. 제출도 같은 잠금을 잡아 다시 읽고, 본문·제출 기록을 한 번에 쓴다.
  test "제출도 행을 잠그고 다시 읽은 뒤 본문과 제출 기록을 함께 쓴다" do
    draft = keyboard_draft
    login_as @student

    locked = false
    autosave_meanwhile = lambda do |report|
      locked = true
      Report.where(id: report.id).update_all(body: "직전에 닿은 자동 저장")
    end
    with_write_before_lock(autosave_meanwhile) do
      assert_enqueued_with job: AiReviewJob do
        patch report_path(draft), params: { report: { body: "제출하며 쓴 최종 글" } }
      end
    end

    assert locked, "제출도 자동 저장과 같은 잠금을 잡아야 둘이 번갈아 끼어들지 않는다"
    draft.reload
    assert draft.submitted?
    assert_equal "제출하며 쓴 최종 글", draft.body
  end

  private

  # 컨트롤러가 행을 잠그기 직전에 한 번만 change 를 실행한다(다른 요청이 먼저 끝난 상황).
  def with_write_before_lock(change)
    ReportLockRaceHook.before_lock = lambda do |report|
      ReportLockRaceHook.before_lock = nil
      change.call(report)
    end
    yield
  ensure
    ReportLockRaceHook.before_lock = nil
  end

  def with_memory_cache
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    yield
  ensure
    Rails.cache = original
  end

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
