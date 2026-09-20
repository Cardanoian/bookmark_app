require "test_helper"

# 제출 버전이 제출·재제출·첨삭·공개를 잇는 흐름(BUG_FIX_PLAN F2 §4.2·§4.4, F3 §5.3). 컨트롤러가 발급한 버전으로
# 잡을 예약하는지, 늦게 도착한 이전 작업이 최신 제출을 건드리지 않는지, 고쳐 다시 낸 글에서 이전 제출의 승인된
# 첨삭이 학생 화면·방송·공유로 새지 않는지, 실패한 첨삭을 같은 버전으로 다시 요청할 수 있는지를 본다.
class ReportReviewVersionTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  BODY = "나는 이 책을 읽고 우리의 삶과 나의 경험을 떠올리며 감동을 느꼈다. 스스로 반성하고 다짐했다.".freeze

  setup do
    @school = School.create!(name: "버전흐름초")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @teacher = User.create!(school: @school, classroom: @classroom, name: "버전담임", role: :teacher, password: "password")
    @classroom.update!(teacher: @teacher)
    @student = User.create!(school: @school, classroom: @classroom, name: "버전학생", password: "password")
    @other_student = User.create!(school: @school, classroom: @classroom, name: "버전친구", password: "password")
  end

  test "새 글 제출과 재제출은 그때 발급한 버전으로 첨삭을 예약한다" do
    login_as @student

    assert_enqueued_with(job: AiReviewJob) do
      post reports_path, params: { report: { book_title: "버전책", body: BODY } }
    end
    report = @student.reports.order(:created_at).last
    assert_equal 1, report.review_version
    assert report.submitted?
    assert_equal [ 1 ], enqueued_versions(report)

    patch report_path(report), params: { report: { body: "#{BODY} 한 문장을 더 썼다." } }
    assert_equal 2, report.reload.review_version
    assert_equal [ 1, 2 ], enqueued_versions(report), "재제출은 새 버전의 작업을 따로 예약한다"

    # 큐에는 두 작업이 다 있다. 어느 순서로 돌아도 최신 제출만 반영된다(이전 버전 작업은 아무것도 하지 않는다).
    perform_enqueued_jobs
    report.reload
    assert report.review_ready?
    assert_equal 2, report.completed_review_version
    assert_equal report.points_awarded, @student.reload.points, "겹친 작업이 포인트를 두 번 주지 않는다"
  end

  # §4.2-4 ①: 글쓴이가 제출된 글의 책·제목만 바꿔도 첨삭 입력이 바뀐 것이다 — 새 버전을 발급한다.
  test "작성자가 제출된 글의 책 제목만 바꿔도 새 버전이 발급되고 이전 승인이 풀린다" do
    report = approved_report(book_title: "처음 고른 책")
    login_as @student

    assert_enqueued_with(job: AiReviewJob) do
      patch report_path(report), params: { report: { book_title: "사실은 다른 책", body: report.body } }
    end

    report.reload
    assert_equal "사실은 다른 책", report.book_title
    assert_equal 2, report.review_version
    assert_not report.reviewed?, "다른 책에 대한 이전 첨삭·승인이 남지 않는다"
    assert_not report.feedback_visible?
    assert_equal [ 2 ], enqueued_versions(report)
  end

  test "작성자가 아무것도 바꾸지 않고 저장하면 버전도 승인도 그대로다" do
    report = approved_report
    login_as @student

    assert_no_enqueued_jobs only: AiReviewJob do
      patch report_path(report), params: { report: { book_title: report.book_title, body: report.body } }
    end

    assert_equal 1, report.reload.review_version
    assert report.feedback_visible?
  end

  # §4.2-4 ②: 담임의 저장은 재제출이 아니다 — 제출된 글의 본문·책을 바꾸는 저장은 받지 않는다.
  test "담임은 제출된 글의 본문과 책을 바꿀 수 없다" do
    report = approved_report
    login_as @teacher

    assert_no_enqueued_jobs only: AiReviewJob do
      patch report_path(report), params: { report: { body: "담임이 고쳐 쓴 본문" } }
      assert_response :unprocessable_entity
      assert_match "글을 쓴 학생만 고칠 수 있어요", response.body
      patch report_path(report), params: { report: { book_title: "담임이 바꾼 책", body: report.body } }
      assert_response :unprocessable_entity
    end

    report.reload
    assert_equal BODY, report.body
    assert_equal "버전책", report.book_title
    assert_equal 1, report.review_version
    assert report.feedback_visible?, "이전 첨삭·승인이 바뀐 입력에 남는 일이 없다 — 입력이 바뀌지 않았다"
  end

  # F3 §5.3: 승인된 글을 고쳐 다시 낸 뒤에는 이전 제출의 첨삭·등급이 어디에도 보이지 않는다.
  test "고쳐 다시 낸 글의 이전 첨삭은 학생 화면·방송·공유 어디에도 보이지 않는다" do
    report = approved_report
    login_as @student
    get report_path(report)
    assert_match "줄거리를 차례대로 잘 정리했어요.", response.body, "사전 조건: 승인된 첨삭은 보인다"

    patch report_path(report), params: { report: { body: "#{BODY} 고쳐 썼다." } }
    report.reload

    get report_path(report)
    assert_no_match "줄거리를 차례대로 잘 정리했어요.", response.body
    assert_no_match "선생님의 5축 첨삭", response.body
    assert_select "span.rounded-full.font-bold", { text: "A", count: 0 }, "이전 제출의 등급을 보이지 않는다"
    assert_match "선생님이 첨삭 중이에요", response.body

    get reports_path
    assert_select "article#report_#{report.id} span.rounded-full.font-bold", count: 0

    broadcast = capture_turbo_stream_broadcasts(report) { report.broadcast_detail_refresh }
    assert_no_match "줄거리를 차례대로 잘 정리했어요.", broadcast.map(&:to_html).join, "방송 payload 에도 없다"

    assert_no_difference "BoardPost.count" do
      post share_report_path(report)
    end
    assert_response :forbidden

    # 새 첨삭이 끝나도 담임이 확인하기 전에는 그대로 비공개다.
    perform_enqueued_jobs
    assert report.reload.review_ready?
    get report_path(report)
    assert_no_match "선생님의 5축 첨삭", response.body
    assert_match "선생님이 확인하고 있어요", response.body
  end

  # F2 §4.4: 현재 버전이 실패로 끝난 글은 같은 버전으로 다시 요청해 복구한다(승인 불가 상태로 멈추지 않는다).
  test "실패한 첨삭은 글쓴이와 담임이 같은 버전으로 다시 요청할 수 있다" do
    report = Report.create!(user: @student, classroom: @classroom, book_title: "실패책", body: BODY,
                            ai_status: :failed, submitted_at: 1.hour.ago, review_version: 1)
    login_as @student

    get report_path(report)
    assert_match "첨삭에 실패했어요", response.body
    assert_select "form[action=?]", retry_review_report_path(report), count: 1

    assert_enqueued_with(job: AiReviewJob) do
      post retry_review_report_path(report)
    end
    assert_redirected_to report_path(report)
    assert report.reload.pending?, "화면이 다시 '첨삭 중'이 된다"
    assert_equal 1, report.review_version, "버전을 올리지 않는다"
    assert_equal [ 1 ], enqueued_versions(report)

    perform_enqueued_jobs
    assert report.reload.review_ready?
    assert_equal report.points_awarded, @student.reload.points

    # 완성된 첨삭은 다시 요청할 수 없다(다시 채점하지 않는다).
    post retry_review_report_path(report)
    assert_response :forbidden
  end

  test "다른 학생은 첨삭을 다시 요청할 수 없고 담임은 검토 화면에서 요청할 수 있다" do
    report = Report.create!(user: @student, classroom: @classroom, book_title: "실패책", body: BODY,
                            ai_status: :failed, submitted_at: 1.hour.ago, review_version: 1)

    login_as @other_student
    post retry_review_report_path(report)
    assert_response :forbidden
    assert report.reload.failed?
    delete session_path

    login_as @teacher
    assert_enqueued_with(job: AiReviewJob) do
      post retry_review_report_path(report), headers: { "HTTP_REFERER" => teacher_review_url(report) }
    end
    assert_redirected_to teacher_review_url(report)
  end

  # 방송으로 다시 그려질 때는 뷰어를 몰라 버튼 대신 이 화면을 다시 여는 링크를 둔다.
  test "실패 방송에는 다시 요청 버튼 대신 화면을 다시 여는 링크가 실린다" do
    report = Report.create!(user: @student, classroom: @classroom, book_title: "실패책", body: BODY,
                            ai_status: :failed, submitted_at: 1.hour.ago, review_version: 1)

    html = capture_turbo_stream_broadcasts(report) { report.broadcast_detail_refresh }.map(&:to_html).join

    assert_match "첨삭에 실패했어요", html
    assert_match report_path(report), html
    assert_no_match retry_review_report_path(report), html
  end

  # §4.2-5: primary DB 와 queue DB 는 따로다 — 큐 적재가 실패해도 이미 커밋된 제출은 그대로 성공이다.
  test "큐 적재가 실패해도 제출은 성공하고 글은 복구 가능한 대기 상태로 남는다" do
    login_as @student
    # perform_later 는 ActiveJob 에서 물려받은 클래스 메서드라, 잠시 덮어썼다가 지우면 원래대로 돌아간다.
    AiReviewJob.define_singleton_method(:perform_later) { |*, **| raise "queue database is down" }
    begin
      post reports_path, params: { report: { book_title: "큐가 죽은 날", body: BODY } }
    ensure
      AiReviewJob.singleton_class.send(:remove_method, :perform_later)
    end

    report = @student.reports.order(:created_at).last
    assert_redirected_to report_path(report)
    assert report.submitted?
    assert report.pending?
    assert_equal 1, report.review_version

    report.update_columns(updated_at: (Report::REVIEW_STALLED_AFTER + 1.minute).ago)
    assert report.reload.review_retryable?, "멈춘 대기 글은 같은 버전으로 다시 예약할 수 있다"
  end

  # ── 독립 리뷰 후속(2026-09-20) ─────────────────────────────────────────────

  # 편집 폼은 제목 칸을 연결한 책의 제목으로 채운다. book_title 열이 그 제목과 다른 글(책 제목이 나중에 정리된 글)을
  # 아무것도 안 고치고 저장해도 재제출이 되면 안 된다 — 승인·교사 편집본·공유가 조용히 사라진다.
  test "책 제목 열이 연결한 책의 제목과 달라도 아무것도 안 고친 저장은 재제출이 아니다" do
    book = Book.create!(title: "마당을 나온 암탉", category: :recommended)
    report = approved_report(book: book, book_title: "마당을나온암탉(옛 표기)",
                             teacher_comment: "잘 썼어요", shared: true)
    BoardPost.create!(report: report)
    unchanged = { report: { book_id: book.id, book_title: book.title, body: report.body.gsub("\n", "\r\n") } }

    login_as @student
    assert_no_enqueued_jobs only: AiReviewJob do
      patch report_path(report), params: unchanged
    end
    assert_redirected_to report_path(report)
    delete session_path

    login_as @teacher
    patch report_path(report), params: unchanged
    assert_redirected_to report_path(report), "담임의 '아무것도 안 고친 저장'도 거부하지 않는다"

    report.reload
    assert_equal 1, report.review_version
    assert report.feedback_visible?
    assert_equal "잘 썼어요", report.teacher_comment
    assert report.shared?
    assert_not_nil report.board_post
  end

  test "연결한 책을 다른 책으로 바꾸면 새 버전이 발급된다" do
    first = Book.create!(title: "처음 고른 책", category: :recommended)
    other = Book.create!(title: "사실은 이 책", category: :recommended)
    report = approved_report(book: first, book_title: first.title)
    login_as @student

    assert_enqueued_with(job: AiReviewJob) do
      patch report_path(report), params: { report: { book_id: other.id, book_title: other.title, body: report.body } }
    end

    assert_equal 2, report.reload.review_version
    assert_not report.reviewed?
  end

  # 고쳐쓰기 초안에서 본문은 그대로 두고 책만 바꿔 '수정하기'를 눌러도 선생님께 간다(첨삭 입력이 달라졌다).
  test "고쳐쓰기 초안에서 책만 바꿔도 제출된다" do
    original = approved_report
    other = Book.create!(title: "사실은 이 책", category: :recommended)
    login_as @student
    post revise_report_path(original)
    revision = @student.reports.where(revision_of: original).last
    assert revision.draft?

    assert_no_enqueued_jobs only: AiReviewJob do # 아무것도 안 고치면 여전히 제출하지 않는다(동일 입력 AI 재호출 방지)
      patch report_path(revision), params: { report: { book_title: revision.book_title, body: revision.body } }
    end
    assert revision.reload.draft?

    assert_enqueued_with(job: AiReviewJob) do
      patch report_path(revision), params: { report: { book_id: other.id, book_title: other.title, body: revision.body } }
    end
    assert revision.reload.submitted?
    assert_equal 1, revision.review_version
  end

  # 첨부(손글씨 원본 사진 등)는 첨삭 입력은 아니지만 담임이 본문과 대조하는 근거다 — 제출된 글에서는 담임이 못 바꾼다.
  test "담임은 제출된 글의 첨부도 바꿀 수 없다" do
    report = approved_report
    login_as @teacher

    patch report_path(report), params: {
      report: { body: report.body, photo: fixture_file_upload("handwriting.png", "image/png") }
    }

    assert_response :unprocessable_entity
    assert_not report.reload.photo.attached?
  end

  # 승인된 객체를 들고 있는 사이 학생이 다시 냈다 — 그 낡은 객체로 방송해도 이전 제출의 첨삭이 실리지 않는다(§4.4).
  test "낡은 객체로 상세를 방송해도 DB 의 최신 상태로 그린다" do
    report = approved_report
    stale = Report.find(report.id)
    assert stale.feedback_visible?

    Report.find(report.id).record_submission!
    html = capture_turbo_stream_broadcasts(report) { stale.broadcast_detail_refresh }.map(&:to_html).join

    assert_no_match "줄거리를 차례대로 잘 정리했어요.", html
    assert_no_match "선생님의 5축 첨삭", html
    assert_match "선생님이 첨삭 중이에요", html
  end

  # '나의 성장'과 인쇄 문서는 글 화면과 같은 공개 조건을 쓴다 — 승인 표시만 있고 완성된 첨삭이 없는 옛 글의 점수를 보이지 않는다.
  test "첨삭 없이 승인된 옛 글은 나의 성장·상태 배지·인쇄 문서 경계에도 들지 않는다" do
    visible = approved_report(book_title: "보이는 글")
    legacy = approved_report(book_title: "옛 글", ai_status: :pending, completed_review_version: nil) # 승인됐지만 첨삭 미완성

    assert_equal [ visible.id ], Report.approved.where(user: @student).pluck(:id)
    assert_equal [ visible.id ], StudentGrowthTimeline.new(@student).entries.map { |entry| entry.report.id }

    login_as @student
    get growth_path
    assert_response :success
    assert_match "보이는 글", response.body
    assert_no_match "옛 글", response.body

    get report_path(legacy)
    assert_select "span.badge", { text: "확인 완료", count: 0 }, "첨삭이 안 보이는 글을 '확인 완료'라고 하지 않는다"
  end

  private

  def approved_report(**attrs)
    Report.create!({ user: @student, classroom: @classroom, book_title: "버전책", body: BODY,
                     avg: 4.5, level: "A", points_awarded: 30,
                     **review_ready_attributes(reviewed: true, reviewed_at: Time.current) }.merge(attrs))
  end

  # 이 글로 예약된 AiReviewJob 들의 expected_review_version(예약 순).
  def enqueued_versions(report)
    enqueued_jobs.select { |job| job["job_class"] == "AiReviewJob" }.filter_map do |job|
      gid, options = job["arguments"]
      next unless gid["_aj_globalid"].end_with?("/Report/#{report.id}")

      options["expected_review_version"]
    end
  end
end
