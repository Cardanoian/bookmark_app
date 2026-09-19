require "test_helper"

class ReportsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @school = School.create!(name: "독후감통합학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @teacher = User.create!(school: @school, classroom: @classroom, name: "통합담임", role: :teacher, password: "password")
    @classroom.update!(teacher: @teacher)
    @student = User.create!(school: @school, classroom: @classroom, name: "통합학생", password: "password")
    @other = User.create!(school: @school, classroom: @classroom, name: "다른통합학생", password: "password")
  end

  test "student creating a report enqueues review and stays pending" do
    login_as @student

    assert_enqueued_with(job: AiReviewJob) do
      post reports_path, params: { report: { book_title: "책", body: "나는 이 책을 읽었다.", input_mode: "keyboard" } }
    end

    report = @student.reports.order(:created_at).last
    assert_not_nil report
    assert report.pending?
    assert_redirected_to report_path(report)
  end

  # 보상 순간 효과음(2026-09-19): 제출하면 다음 화면에 한 번 울릴 sfx 요소가 학생에게 렌더된다.
  test "submitting a report renders the submit sound once for the student" do
    login_as @student
    post reports_path, params: { report: { book_title: "책", body: "나는 이 책을 읽었다.", input_mode: "keyboard" } }
    assert_equal "submit", flash[:sfx]

    follow_redirect!
    assert_select "[data-controller='sfx'][data-sfx-name-value='submit']", 1
    assert_select "button[data-controller='sfx-toggle']", 1, "학생 헤더에 소리 켜기/끄기 버튼"

    get report_path(@student.reports.last)
    assert_select "[data-controller='sfx']", 0, "flash 라 다음 화면에서는 다시 울리지 않는다"
  end

  test "staff never get the sound toggle" do
    login_as @teacher
    get root_path
    assert_select "[data-controller='sfx-toggle']", 0
  end

  # 빈 글은 내지 않는다. 책 제목 칸의 Enter 가 곧 제출이라(자동완성 필드), 제목만 고르고 Enter 를 누른 아이가
  # 빈 글을 내 AI 첨삭이 돌고 교사 큐에 올랐다(자동 저장 5차 리뷰가 범위 밖으로 보고, 2026-09-13).
  test "submitting a new report with a blank body is sent back without creating it" do
    login_as @student

    assert_no_enqueued_jobs only: AiReviewJob do
      assert_no_difference -> { Report.count } do
        post reports_path, params: { report: { book_title: "책", body: "  \r\n ", input_mode: "keyboard" } }
      end
    end
    assert_response :unprocessable_entity
    assert_select "[role=alert]", /독후감 내용이 비어 있어요/
    assert_select "input[name='report[book_title]'][value=?]", "책"
  end

  # 초안의 본문을 모두 지우고 '제출하기'·'수정하기'를 눌러도 빈 글을 내지 않는다(예전에는 본문이 바뀌었다며
  # "고쳐 썼어요"로 제출됐다).
  test "clearing the body and submitting is sent back without submitting" do
    draft = Report.create!(user: @student, classroom: @classroom, book_title: "책", body: "쓰다 만 글", input_mode: :keyboard)
    login_as @student

    assert_no_enqueued_jobs only: AiReviewJob do
      patch report_path(draft), params: { report: { body: "" } }
    end
    assert_response :unprocessable_entity
    assert_select "[role=alert]", /독후감 내용이 비어 있어요/
    draft.reload
    assert draft.draft?
    assert_equal "쓰다 만 글", draft.body
  end

  # 담임도 학생 글을 비워 저장하지 못한다(빈 본문 가드에 담임 예외를 두지 않는다 — 6차 리뷰).
  test "a teacher cannot save a student's draft with a blank body" do
    draft = Report.create!(user: @student, classroom: @classroom, book_title: "책", body: "쓰다 만 글", input_mode: :keyboard)
    login_as @teacher

    patch report_path(draft), params: { report: { body: " " } }
    assert_response :unprocessable_entity
    assert_equal "쓰다 만 글", draft.reload.body
  end

  # 빈 본문으로 되돌려 보낼 때 다른 검증 오류(책 제목)도 함께 알린다 — 한 번에 고칠 것을 다 보여 준다(6차 리뷰).
  test "a blank submission also shows the other validation errors" do
    login_as @student

    post reports_path, params: { report: { book_id: "", book_title: "", body: "", input_mode: "keyboard" } }
    assert_response :unprocessable_entity
    assert_select "[role=alert]", /독후감 내용이 비어 있어요/
    assert_select "[role=alert]", /도서 또는 책 제목이 필요합니다/
  end

  # 챌린지 참여 뒤에 낸 글은 순위에 센다 — 책 제목만 고르고 Enter 를 눌러 빈 본문 422 로 되돌아간 뒤
  # 이어서 써도 마찬가지다. 예전에는 참여 표가 쿠키에 있어서, 되돌아간 요청이 표를 먼저 지우면 그 글이
  # 순위에서 빠졌다(6차 리뷰 F-5). 2026-09-16 에 표를 걷어내고 참여 원장의 기간으로 센다.
  test "reports written after joining count toward the challenge ranking" do
    challenge = Challenge.create!(title: "빈 글 챌린지", scope: :global)
    login_as @student
    post join_challenge_path(challenge)

    post reports_path, params: { report: { book_title: "책", body: "", input_mode: "keyboard" } }
    assert_response :unprocessable_entity

    post reports_path, params: { report: { book_title: "책", body: "이제 쓴 글", input_mode: "keyboard" } }
    post reports_path, params: { report: { book_title: "다른 책", body: "한 편 더 쓴 글", input_mode: "keyboard" } }

    ranking = RankingBoard.new(@student).challenge_ranking(challenge)
    assert_equal 2, ranking.first.score, "참여 뒤에 낸 글은 모두 센다(예전에는 첫 한 편만 셌다)"
  end

  # 기간 밖에 낸 글은 세지 않는다 — 시작 전에 쓴 글(아직 시작 안 한 챌린지에 참여)도, 끝난 뒤에 쓴 글도.
  # 예전에는 남은 쿠키 표가 며칠 뒤 쓴 글에 붙어 순위에 셌다(7차 리뷰 F7-4).
  test "reports outside the challenge window do not count" do
    challenge = Challenge.create!(title: "다음 주 챌린지", scope: :global,
                                  starts_on: 3.days.from_now.to_date, ends_on: 10.days.from_now.to_date)
    login_as @student
    post join_challenge_path(challenge)
    post reports_path, params: { report: { book_title: "시작 전 책", body: "시작 전에 쓴 글", input_mode: "keyboard" } }

    assert_empty RankingBoard.new(@student).challenge_ranking(challenge), "시작 전에 쓴 글은 세지 않는다"

    travel 5.days do
      post reports_path, params: { report: { book_title: "기간 안 책", body: "기간 안에 쓴 글", input_mode: "keyboard" } }
      assert_equal 1, RankingBoard.new(@student).challenge_ranking(challenge).first.score
    end

    travel 20.days do
      post reports_path, params: { report: { book_title: "끝난 뒤 책", body: "끝난 뒤에 쓴 글", input_mode: "keyboard" } }
      assert_equal 1, RankingBoard.new(@student).challenge_ranking(challenge).first.score, "끝난 뒤에 쓴 글은 세지 않는다"
    end
  end

  test "a student cannot view another student's report" do
    report = Report.create!(user: @other, classroom: @classroom, book_title: "남의 글")
    login_as @student
    get report_path(report)
    assert_response :forbidden
  end

  test "student deletes own report from the list" do
    report = Report.create!(user: @student, classroom: @classroom, book_title: "지울 글", body: "본문")
    login_as @student

    get reports_path
    assert_select "form[action=?][method=post]", report_path(report) do
      assert_select "input[name=_method][value=delete]", 1
      assert_select "button", text: "삭제"
    end

    assert_difference("Report.count", -1) do
      delete report_path(report)
    end
    assert_redirected_to reports_path
  end

  test "deleting a pending report safely discards its queued review job" do
    report = Report.create!(user: @student, classroom: @classroom, book_title: "대기 중인 글", body: "본문")
    login_as @student
    AiReviewJob.perform_later(report)

    delete report_path(report)

    assert_nothing_raised { perform_enqueued_jobs }
  end

  test "student cannot delete another student's report" do
    report = Report.create!(user: @other, classroom: @classroom, book_title: "남의 글", body: "본문")
    login_as @student

    assert_no_difference("Report.count") do
      delete report_path(report)
    end
    assert_response :forbidden
  end

  # report-review-gate: AI 첨삭(5축)은 완료 직후가 아니라 교사 승인 후에만 학생에게 보인다
  # (구 동작은 ai_status done 만으로 노출했으나, 미검토 AI 산출물 비공개 게이트로 갱신됨).
  test "show renders the 5축 rubric only after teacher approval, following the offline review job" do
    login_as @student
    perform_enqueued_jobs do
      post reports_path, params: { report: { book_title: "책", body: "나는 우리의 삶을 생각하며 감동을 느꼈다." } }
    end

    report = @student.reports.order(:created_at).last
    assert report.reload.done?

    get report_path(report)
    assert_response :success
    assert_no_match "5축", response.body, "교사 승인 전에는 AI 첨삭을 학생에게 보이면 안 된다"

    delete session_path
    login_as @teacher
    post approve_teacher_review_path(report)
    assert report.reload.reviewed?

    delete session_path
    login_as @student
    get report_path(report)
    assert_response :success
    assert_match "5축", response.body
  end

  test "a teacher (non-student) cannot create a report" do
    login_as @teacher
    post reports_path, params: { report: { book_title: "책", body: "본문" } }
    assert_response :forbidden
  end

  test "revise creates a linked revision that records prev_avg" do
    original = Report.create!(user: @student, classroom: @classroom, book_title: "원본", body: "짧은 글", avg: 3.5)
    login_as @student

    post revise_report_path(original)

    revision = @student.reports.where.not(id: original.id).order(:created_at).last
    assert_equal original.id, revision.revision_of_id
    assert_equal original.avg, revision.prev_avg
    assert_redirected_to edit_report_path(revision)
  end

  # #misc: 고쳐쓰기 초기 상태는 원본과 본문이 동일하므로 재첨삭 AI 를 호출하지 않는다(낭비 방지).
  # 대신 원본 첨삭 결과를 이어받아 done 으로 시작한다.
  test "revise does not re-review an identical body and carries the parent's review forward" do
    original = Report.create!(
      user: @student, classroom: @classroom, book_title: "원본", body: "같은 본문",
      avg: 4.2, level: "A", ai_status: :done,
      rubric: { "content" => 5, "emotion" => 4, "life" => 4, "structure" => 4, "spelling" => 4 }
    )
    login_as @student

    assert_no_enqueued_jobs only: AiReviewJob do
      post revise_report_path(original)
    end

    revision = @student.reports.where.not(id: original.id).order(:created_at).last
    assert revision.done?, "동일 본문은 재첨삭을 건너뛰고 부모 결과를 이어받아 done 으로 시작"
    assert_equal original.rubric, revision.rubric
    assert_equal original.avg, revision.prev_avg
  end

  # 학생이 본문을 실제로 고쳐 저장하면 그때 재첨삭이 예약된다(resubmit? 가드).
  test "editing a revision body re-enqueues review" do
    original = Report.create!(user: @student, classroom: @classroom, book_title: "원본", body: "원래 본문", avg: 3.0, ai_status: :done)
    login_as @student
    post revise_report_path(original)
    revision = @student.reports.where.not(id: original.id).order(:created_at).last

    assert_enqueued_with job: AiReviewJob do
      patch report_path(revision), params: { report: { body: "완전히 새로 고쳐 쓴 본문이에요." } }
    end
  end

  # 수정/고쳐쓰기 단일화(#misc): 상세 화면에는 고쳐쓰기만 노출하고 제자리 '수정' 링크는 제거한다.
  test "report show exposes 고쳐쓰기 but no longer the in-place 수정 link" do
    report = Report.create!(user: @student, classroom: @classroom, book_title: "책", body: "본문", ai_status: :done, submitted_at: Time.current)
    login_as @student

    get report_path(report)
    assert_response :success
    assert_select "form[action=?]", revise_report_path(report), 1, "고쳐쓰기 버튼(button_to)이 있어야 한다"
    assert_select "a.btn.btn-secondary[href=?]", reports_path, text: "목록",
      message: "목록 링크가 다른 액션과 같은 버튼 형태여야 한다"
    assert_select "a[href=?]", edit_report_path(report), count: 0, message: "제자리 수정 링크는 제거되어야 한다"
  end

  # 재첨삭 결과가 새로고침 없이 보이도록 학생 상세 화면은 report 스트림을 구독한다.
  test "report show subscribes to the report stream for live review updates" do
    report = Report.create!(user: @student, classroom: @classroom, book_title: "책", body: "본문", ai_status: :pending)
    login_as @student

    get report_path(report)
    assert_response :success
    assert_select "turbo-cable-stream-source", 1, "상세 화면이 라이브 갱신을 구독해야 한다"
  end

  # 첨삭 완료 시 학생 상세 영역을 실시간 교체하는 방송이 report 스트림으로 나간다.
  test "completing a review broadcasts a live replace to the report's own stream" do
    report = Report.create!(user: @student, classroom: @classroom, book_title: "책",
      body: "나는 우리의 삶을 떠올리며 감동을 느꼈다.", ai_status: :pending)

    broadcasts = capture_turbo_stream_broadcasts(report) do
      perform_enqueued_jobs { AiReviewJob.perform_later(report) }
    end

    assert report.reload.done?
    assert(broadcasts.any? { |stream| stream["action"] == "replace" }, "재첨삭 완료 시 replace 방송이 있어야 한다")
  end

  # dirty-check 배선: 고쳐쓰기(기존 글) 폼은 본문이 달라져야 저장이 눌리도록 report-edit 컨트롤러를 단다.
  test "revision edit form wires the report-edit dirty-check controller" do
    original = Report.create!(user: @student, classroom: @classroom, book_title: "책", body: "원본 본문", ai_status: :done)
    login_as @student
    post revise_report_path(original)
    revision = @student.reports.where.not(id: original.id).order(:created_at).last

    get edit_report_path(revision)
    assert_response :success
    # 자동 저장(report-autosave)이 함께 붙으므로 단어 단위(~=)로 찾는다.
    assert_select "form[data-controller~='report-edit']", 1
    assert_select "textarea[data-report-edit-target='body']", 1
    assert_select "input[type=submit][data-report-edit-target='submit']", 1
  end

  # 새 글 폼은 위저드 초안을 그대로 제출할 수 있어야 하므로 dirty-check 를 걸지 않는다.
  # (모드 선택 화면 도입 후 직접 쓰기 폼은 input_mode=keyboard 로 진입한다.)
  test "new report form is not gated by the dirty-check controller" do
    login_as @student
    get new_report_path(input_mode: :keyboard)
    assert_response :success
    assert_select "form[data-controller~='report-edit']", count: 0
  end

  test "completing a review appends a row to the classroom review queue" do
    login_as @student

    broadcasts = capture_turbo_stream_broadcasts([ @classroom, :review_queue ]) do
      perform_enqueued_jobs do
        post reports_path, params: { report: { book_title: "책", body: "나는 우리의 삶을 떠올렸다." } }
      end
    end

    assert_operator broadcasts.size, :>=, 1
    assert_equal "append", broadcasts.first["action"]
  end

  test "reports index paginates the student's own reports into 20-per-page slices" do
    25.times { |i| Report.create!(user: @student, classroom: @classroom, book_title: "책#{format('%02d', i)}") }
    login_as @student

    get reports_path
    assert_response :success
    assert_select "article", 20
    assert_match "다음", response.body

    get reports_path(page: 2)
    assert_response :success
    assert_select "article", 5
    assert_match "이전", response.body
  end

  private
end
