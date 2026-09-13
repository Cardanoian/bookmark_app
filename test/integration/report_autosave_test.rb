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

# 동시 첫 저장 흉내(3차 리뷰 L4). 새 글을 저장하기 **직전에** 같은 표의 다른 요청이 먼저 초안을 만든 것처럼
# 한 편을 끼워 넣는다 — 컨트롤러가 처음 찾아볼 때는 없던 초안이다. 훅이 없으면 아무 일도 하지 않는다.
module ReportInsertRaceHook
  mattr_accessor :before_insert

  def save(...)
    if new_record? && (hook = ReportInsertRaceHook.before_insert)
      ReportInsertRaceHook.before_insert = nil
      hook.call(self)
    end
    super
  end
end
Report.prepend(ReportInsertRaceHook)

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
  # 다른 기기에서 내고 승인까지 받은 상태(5차 리뷰 F1).
  APPROVED = { submitted_at: Time.current, ai_status: :done, reviewed: true, reviewed_at: Time.current,
               rubric: { content: 3, emotion: 3, life: 3, structure: 3, spelling: 3 }, avg: 3.0, level: "B",
               teacher_comment: "잘 썼어요" }.freeze

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

    # 임시 저장 버튼(HTML)으로 와도 덮지 않는다. 방금 쓴 글은 그대로 보여 준다(글 화면으로 보내면 사라졌다).
    patch report_path(submitted), params: { save_draft: "1", report: { body: "남은 탭의 옛 글" } }
    assert_response :conflict
    assert_equal "제출한 본문", submitted.reload.body
    assert_select "[role=alert]", /이미 제출했어요/
    assert_select "#report_body_field", text: "남은 탭의 옛 글"
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
    assert_select "meta[name='turbo-prefetch'][content='false']", 1,
                  "떠나기 전에 저장을 끝내고 가므로, 저장 전에 미리 받아 둔 화면으로 그리지 않게 한다(6차 리뷰 F-6)"
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
    assert book.searched?, "쓰다 버릴 수도 있는 초안의 책은 정식 도서 목록에 올리지 않는다(2차 리뷰 #12)"

    # 제출(update)로 와도 등록한다 — 자동 저장 뒤로는 제출이 create 가 아니라 update 다.
    other_isbn = "9791111111112"
    with_memory_cache do
      Rails.cache.write("book_meta:#{other_isbn}", { id: nil, title: "다시 고른 책", author: "저자",
                                                     publisher: "출판", isbn: other_isbn, description: "설명" })
      patch report_path(draft), params: { report: { book_id: "", remote_isbn: other_isbn, book_title: "다시 고른 책", body: "다 쓴 글" } }
    end
    assert_equal Book.find_by!(isbn: other_isbn).id, draft.reload.book_id
    assert draft.submitted?
    assert Book.find_by!(isbn: other_isbn).recommended?, "낸 글의 책은 정식 도서 목록에 오른다"
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
    assert_select "input[name='autosave_key']", 0
    # 버전 칸은 둔다 — 담임의 저장도 학생이 그사이 더 쓴 글을 덮지 않게(3차 리뷰 M2).
    assert_select "input[name='draft_version'][value=?]", draft.draft_version
  end


  # --- 2차 코드 리뷰(e411848) 후속 ---

  # 단계 학습은 본문 전체를 새 글 주소에 실어 넘긴다. 주소 원문을 세션 쿠키에 넣던 때는 쿠키 한도(4KB)를
  # 넘어 첫 저장이 500 으로 끝났고, 초안은 이미 저장된 뒤라 재시도마다 초안이 늘었다(#1).
  test "본문이 실린 긴 새 글 주소도 첫 자동 저장이 되고, 같은 주소로 다시 오면 그 초안을 연다" do
    origin = new_report_path(input_mode: :keyboard, report: { book_title: @book.title, body: "[책 고르기] #{"마틸다를 골랐어요. " * 300}" })
    assert_operator origin.bytesize, :>, 4096
    login_as @student

    post reports_path, params: { save_draft: "1", autosave_origin: origin, autosave_key: "long-origin-key",
                                 report: { book_title: @book.title, body: "단계 학습에서 넘어온 글" } },
                       headers: JSON_HEADERS
    assert_response :created
    draft = Report.find(response.parsed_body["id"])
    assert_equal Digest::SHA256.hexdigest(origin), draft.autosave_origin_digest, "주소 원문이 아니라 지문을 초안에 둔다"

    get origin
    assert_redirected_to edit_report_path(draft)
  end

  # 서버는 저장을 마쳤는데 응답만 끊긴 경우(시간 초과·연결 끊김) 화면의 버전 표는 옛 값이다. 같은 화면이
  # 다시 보낸 그 저장을 "다른 곳에서 고쳤다"로 거절하면 탭 하나만 쓰는데도 멈췄다(#2).
  test "같은 화면이 응답만 잃고 다시 보낸 저장은 버전이 뒤처져도 받고, 다른 화면이면 거절한다" do
    draft = keyboard_draft
    seen = draft.draft_version
    login_as @student

    patch report_path(draft), params: { save_draft: "1", draft_version: seen, autosave_key: "tab-one-key",
                                        report: { body: "한 줄 더 쓴 글" } }, headers: JSON_HEADERS
    assert_response :success # 서버는 저장했지만 브라우저는 이 응답을 못 받았다고 치자.

    patch report_path(draft), params: { save_draft: "1", draft_version: seen, autosave_key: "tab-one-key",
                                        report: { body: "한 줄 더 쓴 글, 그리고 또 한 줄" } }, headers: JSON_HEADERS
    assert_response :success, "마지막으로 쓴 것이 이 화면이면 거짓 충돌이 아니다"
    assert_equal "한 줄 더 쓴 글, 그리고 또 한 줄", draft.reload.body

    patch report_path(draft), params: { save_draft: "1", draft_version: seen, autosave_key: "tab-two-key",
                                        report: { body: "다른 탭의 옛 글" } }, headers: JSON_HEADERS
    assert_response :conflict
    assert_equal "한 줄 더 쓴 글, 그리고 또 한 줄", draft.reload.body
  end

  # "다른 곳에서 고쳤어요"를 본 아이가 누르는 '임시 저장'·'제출하기'가 우회로였다(#3). 이 화면의 글은
  # 지우지 않고 다시 보여 주되, 한 번 더 누를 때만 이 글로 바꾼다.
  test "다른 곳에서 더 고친 초안에 임시 저장 버튼을 누르면 쓴 글을 보여 주고, 한 번 더 눌러야 바꾼다" do
    draft = keyboard_draft
    seen = draft.draft_version
    travel 1.minute do
      draft.update!(body: "집에서 더 쓴 글이에요.")
    end
    login_as @student

    patch report_path(draft), params: { save_draft: "1", draft_version: seen, report: { body: "옛 화면에서 쓴 글" } }
    assert_response :conflict
    assert_equal "집에서 더 쓴 글이에요.", draft.reload.body, "버튼 한 번으로는 다른 곳의 글을 덮지 않는다"
    assert_select "[role=alert]", /다른 탭이나 기기에서 이 글을 더 고쳤어요/
    assert_select "a[href=?]", edit_report_path(draft), text: "최신 글 보기"
    assert_select "#report_body_field", text: "옛 화면에서 쓴 글"
    assert_select "form[data-report-autosave-enabled-value='false']", 1, "입력만으로 덮지 않게 이 화면에서는 자동 저장을 끈다"
    assert_select "input[name='save_draft']", 1
    current = css_select("input[name='draft_version']").first["value"]
    assert_equal draft.draft_version, current, "한 번 더 누르면 통과하도록 최신 버전을 싣는다"

    patch report_path(draft), params: { save_draft: "1", draft_version: current, report: { body: "옛 화면에서 쓴 글" } }
    assert_redirected_to edit_report_path(draft)
    assert_equal "옛 화면에서 쓴 글", draft.reload.body
  end

  test "다른 곳에서 더 고친 초안을 제출하면 바로 내지 않고 한 번 더 확인받는다" do
    draft = keyboard_draft
    seen = draft.draft_version
    travel 1.minute do
      draft.update!(body: "집에서 더 쓴 글이에요.")
    end
    login_as @student

    assert_no_enqueued_jobs only: AiReviewJob do
      patch report_path(draft), params: { draft_version: seen, report: { body: "옛 화면에서 쓴 글" } }
    end
    assert_response :conflict
    assert draft.reload.draft?
    assert_equal "집에서 더 쓴 글이에요.", draft.body

    assert_enqueued_with job: AiReviewJob do
      patch report_path(draft), params: { draft_version: draft.draft_version, report: { body: "옛 화면에서 쓴 글" } }
    end
    assert draft.reload.submitted?
    assert_equal "옛 화면에서 쓴 글", draft.body
  end

  # 첫 저장이 시간 초과로 끊겨도 서버는 이미 초안을 만들었을 수 있다. 같은 화면 표로 다시 오면 새로
  # 만들지 않고 그 초안을 잇는다. 첫 저장을 기다리던 제출도 마찬가지다(#4).
  test "같은 화면 표로 다시 온 첫 저장·제출은 초안을 새로 만들지 않고 그 초안을 잇는다" do
    login_as @student
    params = { save_draft: "1", autosave_key: "first-save-key", report: { book_id: @book.id, book_title: @book.title, body: "쓰기 시작한 글" } }

    assert_difference -> { Report.count }, 1 do
      post reports_path, params: params, headers: JSON_HEADERS
      post reports_path, params: params.deep_merge(report: { body: "쓰기 시작한 글에 더 쓴 글" }), headers: JSON_HEADERS
    end
    draft = @student.reports.sole
    assert_equal draft.id, response.parsed_body["id"]
    assert_equal "쓰기 시작한 글에 더 쓴 글", draft.body

    assert_no_difference -> { Report.count } do
      assert_enqueued_with job: AiReviewJob do
        post reports_path, params: { autosave_key: "first-save-key", report: { book_id: @book.id, book_title: @book.title, body: "다 쓴 글" } }
      end
    end
    assert draft.reload.submitted?
    assert_equal "다 쓴 글", draft.body
  end

  test "다른 글을 만든 화면 표가 실려 와도 500 없이 저장하고 그 글은 건드리지 않는다" do
    other = Report.create!(user: @student, classroom: @classroom, book_title: "다른 책", body: "다른 글",
                           input_mode: :keyboard, autosave_key: "taken-key")
    draft = keyboard_draft
    login_as @student

    patch report_path(draft), params: { save_draft: "1", autosave_key: "taken-key", report: { body: "이어 쓴 글" } }, headers: JSON_HEADERS
    assert_response :success
    assert_equal "이어 쓴 글", draft.reload.body
    assert_nil draft.autosave_key, "만든 화면 표는 새 글을 만들 때만 붙는다"
    assert_equal "다른 글", other.reload.body
    assert_equal "taken-key", other.autosave_key
  end


  # --- 3차 코드 리뷰(b67c678) 후속 ---

  # 집에서 이미 낸 글을, 초안일 때 열어 둔 학교 태블릿의 '제출하기'가 옛 글로 덮고 AI 첨삭을 다시 걸었다(H1).
  test "초안일 때 연 화면의 제출은 그사이 다른 곳에서 낸 글을 바꾸지 않는다" do
    draft = keyboard_draft
    seen = draft.draft_version
    travel 1.minute do
      draft.update!(body: "집에서 다 쓰고 낸 글이에요.", submitted_at: Time.current)
    end
    login_as @student

    assert_no_enqueued_jobs only: AiReviewJob do
      patch report_path(draft), params: { draft_version: seen, report: { body: "학교 태블릿의 옛 글" } }
    end
    assert_response :conflict
    assert_equal "집에서 다 쓰고 낸 글이에요.", draft.reload.body
    assert_select "[role=alert]", /이미 제출했어요/
    assert_select "a[href=?]", report_path(draft), text: "글 보러 가기"
    assert_select "#report_body_field", text: "학교 태블릿의 옛 글"
    assert_select "input[type=submit]", 0, "이미 낸 글을 이 화면의 글로 바꾸는 버튼을 두지 않는다"
    assert_select "form[data-report-autosave-unsaved-value='true']", 1, "쓴 글이 저장되지 않았으니 떠날 때 붙잡는다"
  end

  test "승인까지 끝난 글도 옛 화면의 제출이 승인을 풀지 않는다" do
    draft = keyboard_draft
    seen = draft.draft_version
    travel 1.minute do
      draft.update!(body: "집에서 낸 글", submitted_at: Time.current, ai_status: :done, reviewed: true, reviewed_at: Time.current,
                    rubric: { content: 3, emotion: 3, life: 3, structure: 3, spelling: 3 }, teacher_comment: "잘 썼어요")
    end
    login_as @student

    patch report_path(draft), params: { draft_version: seen, report: { body: "옛 화면의 글" } }
    assert_response :conflict
    draft.reload
    assert draft.reviewed?
    assert_equal "잘 썼어요", draft.teacher_comment
    assert_equal "집에서 낸 글", draft.body
  end

  test "같은 화면 표로 늦게 온 새 글 제출은 이미 낸 글을 다시 내지 않는다" do
    login_as @student
    post reports_path, params: { save_draft: "1", draft_version: "", autosave_key: "late-submit-key",
                                 report: { book_id: @book.id, book_title: @book.title, body: "쓰기 시작한 글" } }, headers: JSON_HEADERS
    draft = @student.reports.sole
    patch report_path(draft), params: { draft_version: draft.draft_version, report: { body: "다 쓴 글" } }
    assert draft.reload.submitted?

    assert_no_enqueued_jobs only: AiReviewJob do
      post reports_path, params: { draft_version: "", autosave_key: "late-submit-key",
                                   report: { book_id: @book.id, book_title: @book.title, body: "늦게 도착한 제출" } }
    end
    assert_response :conflict
    assert_equal 1, @student.reports.count
    assert_equal "다 쓴 글", draft.reload.body
  end

  # 같은 화면이라도 이미 저장한 것보다 앞선 순번의 요청은 받지 않는다 — 서버에서 오래 막힌 옛 저장이 재시도
  # 뒤에 처리되면 새 글이 되돌아갔다(M1). 같은 순번(응답만 잃은 재전송)은 같은 내용이라 받는다.
  test "같은 화면이라도 늦게 도착한 앞선 순번의 저장은 새 글을 되돌리지 않는다" do
    draft = keyboard_draft
    seen = draft.draft_version
    login_as @student
    save = ->(seq, body) {
      patch report_path(draft), params: { save_draft: "1", draft_version: seen, autosave_key: "tab-key-01", autosave_seq: seq,
                                          report: { body: body } }, headers: JSON_HEADERS
    }

    save.call(5, "다섯 번째 입력까지 쓴 글")
    assert_response :success
    save.call(3, "세 번째 입력까지 쓴 옛 글") # 오래 막혔다가 늦게 도착한 옛 요청
    assert_response :conflict
    assert_equal "다섯 번째 입력까지 쓴 글", draft.reload.body

    save.call(5, "다섯 번째 입력까지 쓴 글") # 응답만 잃고 다시 보낸 같은 요청
    assert_response :success
    save.call(8, "여덟 번째 입력까지 쓴 글")
    assert_response :success
    assert_equal "여덟 번째 입력까지 쓴 글", draft.reload.body
  end

  # 담임이 학생 초안을 고치면 "마지막으로 쓴 화면"이 비워져, 학생 옛 탭의 자동 저장이 담임 수정을 덮지 못한다(M2).
  test "담임이 고친 학생 초안은 학생 옛 탭의 자동 저장이 덮지 못한다" do
    draft = keyboard_draft
    seen = draft.draft_version
    login_as @student
    patch report_path(draft), params: { save_draft: "1", draft_version: seen, autosave_key: "student-tab", autosave_seq: 3,
                                        report: { body: "학생이 쓰던 글" } }, headers: JSON_HEADERS
    student_seen = response.parsed_body["draft_version"]
    delete session_path

    login_as @teacher
    travel 1.minute do
      patch report_path(draft), params: { draft_version: student_seen, report: { body: "담임이 맞춤법을 고친 글" } }
    end
    assert_equal "담임이 맞춤법을 고친 글", draft.reload.body
    assert_nil draft.autosave_writer_key
    delete session_path

    login_as @student
    patch report_path(draft), params: { save_draft: "1", draft_version: student_seen, autosave_key: "student-tab", autosave_seq: 9,
                                        report: { body: "학생 옛 탭의 글" } }, headers: JSON_HEADERS
    assert_response :conflict
    assert_equal "담임이 맞춤법을 고친 글", draft.reload.body
  end

  # 첫 저장 응답을 잃은 사이 다른 탭이 그 초안을 저장해도, 첫 화면의 재시도는 제 초안을 찾는다(L1) —
  # 표를 "마지막으로 쓴 화면"이 아니라 "만든 화면"으로 찾는다. 찾은 뒤에는 **다른 탭의 글을 덮지 않는다**
  # (4차 리뷰 H-A — 버전을 모르는 이어 쓰기가 그 글을 덮던 틈).
  test "첫 저장 응답을 잃은 사이 다른 탭이 저장해도 첫 화면의 재시도는 초안을 새로 만들지도, 덮지도 않는다" do
    login_as @student
    first = { save_draft: "1", draft_version: "", autosave_key: "creator-tab", autosave_seq: 1,
              report: { book_id: @book.id, book_title: @book.title, body: "쓰기 시작한 글" } }
    post reports_path, params: first, headers: JSON_HEADERS
    draft = @student.reports.sole

    patch report_path(draft), params: { save_draft: "1", draft_version: draft.draft_version, autosave_key: "other-tab", autosave_seq: 1,
                                        report: { body: "다른 탭에서 이어 쓴 글" } }, headers: JSON_HEADERS
    assert_equal "other-tab", draft.reload.autosave_writer_key

    assert_no_difference -> { Report.count } do
      post reports_path, params: first.deep_merge(autosave_seq: 2, report: { body: "첫 화면의 재시도" }), headers: JSON_HEADERS
    end
    assert_response :conflict
    assert_equal "stale", response.parsed_body["error"]
    assert_equal edit_report_path(draft), response.parsed_body["edit_url"], "새로 고치면 최신 글이 열리도록 주소를 알려 준다"
    assert_equal "다른 탭에서 이어 쓴 글", draft.reload.body
  end

  # 같은 표의 첫 저장 두 개가 거의 동시에 들어오면, 먼저 찾아본 순간에는 없던 초안을 다른 요청이 먼저 만든다.
  # 그때는 유일 인덱스가 둘째를 막고 그 초안을 잇는다(앞의 "같은 표 잇기"와 따로 지킨다 — L4·테스트 공백).
  test "같은 표의 첫 저장이 동시에 들어와도 초안은 한 편이다" do
    login_as @student
    with_competing_insert do
      assert_difference -> { Report.count }, 1 do
        post reports_path, params: { save_draft: "1", draft_version: "", autosave_key: "race-key", autosave_seq: 2,
                                     report: { book_id: @book.id, book_title: @book.title, body: "늦게 들어온 첫 저장" } },
                           headers: JSON_HEADERS
      end
    end
    assert_response :success
    draft = @student.reports.sole
    assert_equal draft.id, response.parsed_body["id"]
    assert_equal "늦게 들어온 첫 저장", draft.body
  end


  # --- 4차 코드 리뷰(bce37c8) 후속 ---

  test "같은 화면의 동시 첫 저장이라도 앞선 순번이 뒤 순번의 저장을 되돌리지 않는다" do
    login_as @student
    with_competing_insert(seq: 9) do
      post reports_path, params: { save_draft: "1", draft_version: "", autosave_key: "race-key", autosave_seq: 2,
                                   report: { book_id: @book.id, book_title: @book.title, body: "앞선 순번의 첫 저장" } },
                         headers: JSON_HEADERS
    end
    assert_response :conflict
    assert_equal "먼저 들어온 첫 저장", @student.reports.sole.body
  end

  # 첫 저장 응답을 잃은 태블릿 화면에서 '제출하기'를 누르면(새 글 폼이라 create 로 간다) 그사이 집에서 쓴
  # 글이 옛 글로 덮여 제출됐다(4차 리뷰 H-A). 쓴 글을 보여 주며 한 번 더 확인받는다.
  test "첫 저장 응답을 잃은 새 글 화면의 제출은 그사이 다른 곳에서 쓴 글을 바로 덮지 않는다" do
    login_as @student
    base = { draft_version: "", autosave_key: "tablet-tab", opened_as_draft: "1",
             report: { book_id: @book.id, book_title: @book.title } }
    post reports_path, params: base.deep_merge(save_draft: "1", autosave_seq: 1, report: { body: "태블릿에서 쓴 첫 줄" }), headers: JSON_HEADERS
    draft = @student.reports.sole
    patch report_path(draft), params: { save_draft: "1", draft_version: draft.draft_version, autosave_key: "home-computer", autosave_seq: 57,
                                        report: { body: "집에서 이어 쓴 긴 글" } }, headers: JSON_HEADERS

    assert_no_enqueued_jobs only: AiReviewJob do
      post reports_path, params: base.deep_merge(autosave_seq: 11, report: { body: "태블릿에서 쓴 첫 줄" })
    end
    assert_response :conflict
    assert draft.reload.draft?
    assert_equal "집에서 이어 쓴 긴 글", draft.body
    assert_select "[role=alert]", /다른 탭이나 기기에서 이 글을 더 고쳤어요/
    assert_select "#report_body_field", text: "태블릿에서 쓴 첫 줄"
  end

  test "담임이 고친 초안도 학생 첫 화면의 재시도가 덮지 못한다" do
    login_as @student
    first = { save_draft: "1", draft_version: "", autosave_key: "student-first", autosave_seq: 1,
              report: { book_id: @book.id, book_title: @book.title, body: "학생이 쓴 첫 줄" } }
    post reports_path, params: first, headers: JSON_HEADERS
    draft = @student.reports.sole
    delete session_path

    login_as @teacher
    patch report_path(draft), params: { opened_as_draft: "1", draft_version: draft.draft_version, report: { body: "담임이 고친 글" } }
    delete session_path

    login_as @student
    post reports_path, params: first.merge(autosave_seq: 3), headers: JSON_HEADERS
    assert_response :conflict
    assert_equal "담임이 고친 글", draft.reload.body
  end

  # 사진 첫 제출 화면에는 버전 칸이 없어(판독 잡이 수정 시각을 바꾼다) "초안일 때 연 화면" 보호가 빠졌었다.
  # 집에서 내고 승인까지 받은 글을 그 화면의 '제출하기'가 판독 원문으로 덮고 승인을 풀었다(4차 리뷰 H-B).
  test "사진 첫 제출 화면의 제출도 그사이 낸·승인된 글을 바꾸지 않는다" do
    draft = Report.create!(user: @student, classroom: @classroom, book_title: "사진 책",
                           input_mode: :ocr, body: "사진에서 읽은 글", ai_status: :done)
    login_as @student
    get edit_report_path(draft)
    assert_select "input[name='opened_as_draft'][value='1']", 1
    assert_select "input[name='draft_version']", 0, "판독 잡이 수정 시각을 바꾸므로 사진 첫 제출 화면에는 버전 칸이 없다"

    draft.update!(body: "집에서 고쳐 낸 글", submitted_at: Time.current, reviewed: true, reviewed_at: Time.current,
                  rubric: { content: 3, emotion: 3, life: 3, structure: 3, spelling: 3 }, teacher_comment: "좋아요")

    assert_no_enqueued_jobs only: AiReviewJob do
      patch report_path(draft), params: { opened_as_draft: "1", report: { body: "사진에서 읽은 글" } }
    end
    assert_response :conflict
    draft.reload
    assert draft.reviewed?
    assert_equal "좋아요", draft.teacher_comment
    assert_equal "집에서 고쳐 낸 글", draft.body
  end

  # 입력 오류로 다시 그린 화면도 저장 안 된 글을 보여 준다 — 떠날 때 붙잡는다(4차 리뷰 L-B).
  test "입력 오류로 다시 그린 편집 화면은 저장 안 됨으로 시작한다" do
    draft = keyboard_draft
    login_as @student

    patch report_path(draft), params: { opened_as_draft: "1", draft_version: draft.draft_version,
                                        report: { book_id: "", book_title: "", body: "제목을 지우고 낸 글" } }
    assert_response :unprocessable_entity
    assert_select "form[data-report-autosave-unsaved-value='true']", 1
  end

  test "담임이 받는 충돌 안내는 학생 기준 문구가 아니다" do
    draft = keyboard_draft
    seen = draft.draft_version
    travel 1.minute do
      draft.update!(body: "학생이 그사이 더 쓴 글")
    end
    login_as @teacher

    patch report_path(draft), params: { opened_as_draft: "1", draft_version: seen, report: { body: "담임이 고친 글" } }
    assert_response :conflict
    assert_select "[role=alert]", /학생이 그사이 이 글을 더 썼어요/
    assert_select "[role=alert]", { text: /다른 탭이나 기기에서/, count: 0 }

    draft.update!(submitted_at: Time.current)
    patch report_path(draft), params: { opened_as_draft: "1", draft_version: draft.draft_version, report: { body: "담임이 고친 글" } }
    assert_response :conflict
    assert_select "[role=alert]", /학생이 그사이 이 글을 제출했어요/
    assert_select "[role=alert]", { text: /고쳐쓰기/, count: 0 }
  end

  # --- 5차 코드 리뷰(ee11907) 후속 ---

  # '이미 제출했어요' 화면은 버튼을 없앴지만 폼과 text 칸 하나(책 제목)가 남아, HTML 규칙상 Enter 가 폼을
  # 제출한다. 그 화면에 `opened_as_draft` 가 빠져 있어 일반 수정으로 처리됐다 — 승인된 글이 옛 탭의 글로 덮이고
  # 승인이 풀렸다(F1). 여기서는 그 화면이 보내는 칸을 그대로 다시 보내 암묵 제출을 흉내 낸다.
  test "이미 제출 화면의 폼을 다시 보내도(Enter 암묵 제출) 승인된 글을 바꾸지 않는다" do
    draft = keyboard_draft
    login_as @student
    get edit_report_path(draft)
    seen = form_fields(response.body)
    draft.update!(APPROVED.merge(body: "집에서 다 쓰고 낸 글"))

    patch report_path(draft), params: seen.merge("report[body]" => "학교 태블릿의 옛 글")
    assert_response :conflict
    conflict = form_fields(response.body)
    assert_equal "1", conflict["opened_as_draft"], "이미 제출 화면도 초안일 때 연 화면이다"

    assert_no_enqueued_jobs only: AiReviewJob do
      patch report_path(draft), params: conflict
    end
    assert_response :conflict
    draft.reload
    assert_equal "집에서 다 쓰고 낸 글", draft.body
    assert draft.reviewed?
    assert_equal "잘 썼어요", draft.teacher_comment
  end

  test "사진 첫 제출·담임 화면의 이미 제출 화면도 다시 보내면 거절한다" do
    photo = Report.create!(user: @student, classroom: @classroom, book_title: "사진 책",
                           input_mode: :ocr, body: "사진에서 읽은 글", ai_status: :done)
    login_as @student
    get edit_report_path(photo)
    seen = form_fields(response.body)
    photo.update!(APPROVED.merge(body: "집에서 고쳐 내고 승인받은 글"))
    patch report_path(photo), params: seen
    assert_response :conflict
    patch report_path(photo), params: form_fields(response.body)
    assert_response :conflict
    assert photo.reload.reviewed?
    assert_equal "집에서 고쳐 내고 승인받은 글", photo.body

    draft = keyboard_draft
    delete session_path
    login_as @teacher
    get edit_report_path(draft)
    seen = form_fields(response.body)
    travel 1.minute do
      draft.update!(body: "학생이 집에서 다 쓰고 낸 글", submitted_at: Time.current)
    end
    patch report_path(draft), params: seen.merge("report[body]" => "담임이 옛 탭에서 고친 글")
    assert_response :conflict
    patch report_path(draft), params: form_fields(response.body)
    assert_response :conflict
    assert_equal "학생이 집에서 다 쓰고 낸 글", draft.reload.body
  end

  # 본문을 비우고 누른 '임시 저장'의 입력 오류 화면이 보낸 칸 대신 저장된 제목·본문을 보여 줬다(LOW-a) —
  # 바꾼 제목이 조용히 사라지고, 저장된 글을 보여 주면서 떠날 때는 붙잡았다.
  test "빈 본문 임시 저장의 입력 오류 화면은 보낸 칸을 그대로 보여 준다" do
    draft = keyboard_draft
    login_as @student

    patch report_path(draft), params: { save_draft: "1", opened_as_draft: "1", draft_version: draft.draft_version,
                                        report: { book_id: "", book_title: "새로 고친 제목", body: "" } }
    assert_response :unprocessable_entity
    assert_select "input[name='report[book_title]'][value=?]", "새로 고친 제목"
    assert_select "#report_body_field", text: ""
    assert_equal "쓰다 만 글이에요.", draft.reload.body, "저장하지는 않는다"
  end

  # 자동 저장이 "이미 제출한 글"로 멈추면 새로 고칠 곳을 알려 준다(LOW-b). 주소가 없던 때는 안내대로 새로
  # 고치면 편집 화면이면 배너 없는 '수정하기' 폼이, 새 글 화면이면 빈 새 글이 열렸다.
  test "이미 제출한 글에 온 자동 저장의 409 는 그 글 주소를 알려 준다" do
    draft = keyboard_draft
    draft.update!(submitted_at: Time.current)
    login_as @student

    patch report_path(draft), params: { save_draft: "1", draft_version: draft.draft_version, report: { body: "뒤늦은 저장" } },
                              headers: JSON_HEADERS
    assert_response :conflict
    assert_equal "already_submitted", response.parsed_body["error"]
    assert_equal report_path(draft), response.parsed_body["report_url"]
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

  # 새 글이 저장되기 직전, 같은 표로 다른 요청이 먼저 만든 초안을 끼워 넣는다.
  # 끼워 넣는 초안은 같은 화면의 다른 요청이 만든 것이다 — 만든 화면·마지막으로 쓴 화면이 이 표이고 순번은 seq.
  def with_competing_insert(seq: 1)
    ReportInsertRaceHook.before_insert = lambda do |report|
      Report.create!(user: report.user, classroom: report.classroom, book_title: report.book_title,
                     body: "먼저 들어온 첫 저장", input_mode: :keyboard, autosave_key: report.autosave_key,
                     autosave_writer_key: report.autosave_key, autosave_seq: seq)
    end
    yield
  ensure
    ReportInsertRaceHook.before_insert = nil
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

  # 독후감 폼이 브라우저에서 보내는 칸(이름이 있고, 비활성이 아니고, 제출 버튼이 아닌 것) — Enter 암묵 제출과 같다.
  def form_fields(html)
    form = Nokogiri::HTML(html).at_css("form[data-controller~='report-autosave']")
    fields = {}
    form.css("input[name]").each do |input|
      next if %w[submit button].include?(input["type"]) || input.key?("disabled")

      fields[input["name"]] = input["value"].to_s
    end
    form.css("textarea[name]").each { |area| fields[area["name"]] = area.text.sub(/\A\n/, "") }
    fields
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
