require "test_helper"

class TeacherReviewsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @school = School.create!(name: "검토통합학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @teacher = User.create!(school: @school, classroom: @classroom, name: "검토담임", role: :teacher, password: "password")
    @classroom.update!(teacher: @teacher)

    @other_classroom = Classroom.create!(school: @school, grade: 5, class_no: 2)
    @other_teacher = User.create!(school: @school, classroom: @other_classroom, name: "다른담임", role: :teacher, password: "password")
    @other_classroom.update!(teacher: @other_teacher)

    @student = User.create!(school: @school, classroom: @classroom, name: "검토학생", password: "password")
    @report = Report.create!(
      user: @student, classroom: @classroom, book_title: "책", body: "본문",
      ai_status: :done, avg: 3.0, level: "B", reviewed: false, submitted_at: Time.current
    )
    @reviewed_report = Report.create!(
      user: @student, classroom: @classroom, book_title: "이미검토한책", body: "검토완료 본문",
      ai_status: :done, avg: 4.0, level: "A", reviewed: true, reviewed_at: 1.day.ago, submitted_at: Time.current
    )
  end

  test "list shows the담임's pending classroom reports" do
    login_as @teacher
    get teacher_reviews_path
    assert_response :success
    assert_match @student.name, response.body
  end

  # --- 검토 상태 필터(모두/미검토/검토완료) ---

  # 필터 미지정 기본값은 미검토다(교사의 '할 일 목록' 워크플로 유지).
  test "the list defaults to unreviewed reports and hides reviewed ones" do
    login_as @teacher
    get teacher_reviews_path

    assert_response :success
    assert_select "article#report_#{@report.id}"
    assert_select "article#report_#{@reviewed_report.id}", count: 0
  end

  test "status=reviewed shows only reviewed reports without approval controls" do
    login_as @teacher
    get teacher_reviews_path(status: "reviewed")

    assert_response :success
    assert_select "article#report_#{@reviewed_report.id}"
    assert_select "article#report_#{@report.id}", count: 0
    assert_select "input[name='report_ids[]']", { count: 0 },
      "검토완료 행에는 일괄 승인 체크박스가 없어야 한다"
    assert_select "form#batch_approve_reports", { count: 0 },
      "검토완료 탭에는 승인할 대상이 없으므로 일괄 승인 폼도 렌더하지 않는다"
    assert_select "form[action=?]", approve_teacher_review_path(@reviewed_report), count: 0
  end

  test "status=all shows both reviewed and unreviewed reports" do
    login_as @teacher
    get teacher_reviews_path(status: "all")

    assert_response :success
    assert_select "article#report_#{@report.id}"
    assert_select "article#report_#{@reviewed_report.id}"
  end

  # 위조·오타 status 는 조용히 기본값(미검토)으로 폴백해야 한다.
  test "an unknown status falls back to the pending filter" do
    login_as @teacher
    get teacher_reviews_path(status: "hacked")

    assert_response :success
    assert_select "article#report_#{@report.id}"
    assert_select "article#report_#{@reviewed_report.id}", count: 0
  end

  test "the list renders all three status filter links" do
    login_as @teacher
    get teacher_reviews_path

    assert_select "a[href=?]", teacher_reviews_path(status: "all")
    assert_select "a[href=?]", teacher_reviews_path(status: "pending")
    assert_select "a[href=?]", teacher_reviews_path(status: "reviewed")
  end

  # 검토완료 글이 목록에 노출되면서 id 를 알아내기 쉬워졌다. batch_approve 는 pending_scope
  # 게이트로 이미 승인된 글을 다시 finalize_approval 캐스케이드에 태우지 않아야 한다.
  test "batch_approve ignores already reviewed reports" do
    original_reviewed_at = @reviewed_report.reviewed_at
    login_as @teacher

    post batch_approve_teacher_reviews_path, params: { report_ids: [ @report.id, @reviewed_report.id ] }

    assert @report.reload.reviewed?
    assert_equal original_reviewed_at.to_i, @reviewed_report.reload.reviewed_at.to_i,
      "이미 승인한 독후감은 batch_approve 로 재승인되지 않아야 한다"
  end

  test "the list paginates and carries the status filter to the next page" do
    login_as @teacher
    21.times { |i| Report.create!(user: @student, classroom: @classroom, book_title: "검토완료#{i}", ai_status: :done, reviewed: true, reviewed_at: i.hours.ago, submitted_at: Time.current) }

    get teacher_reviews_path(status: "reviewed")
    assert_response :success
    assert_select "article.card", count: Teacher::ReviewsController::PER_PAGE
    assert_select "a[href=?]", teacher_reviews_path(status: "reviewed", page: 2)

    get teacher_reviews_path(status: "reviewed", page: 2)
    assert_response :success
    assert_select "article.card", count: 2 # 22건 중 나머지(@reviewed_report 포함)
  end

  # 승인은 reviewed_at 을 덮어쓰고 뱃지·진화·미션·챌린지·몬스터 해금 캐스케이드를 재실행하므로,
  # 목록에서 도달 가능해진 검토완료 상세에는 노출하지 않는다(저장은 유지).
  test "the show page hides the approve button once the report is reviewed" do
    login_as @teacher

    get teacher_review_path(@report)
    assert_select "form[action=?]", approve_teacher_review_path(@report)

    get teacher_review_path(@reviewed_report)
    assert_select "form[action=?]", approve_teacher_review_path(@reviewed_report), count: 0
    assert_match "이미 승인한 독후감이에요", response.body
  end

  test "individual and batch approval controls submit to separate endpoints" do
    login_as @teacher
    get teacher_reviews_path

    assert_select "form#batch_approve_reports[action=?]", batch_approve_teacher_reviews_path do
      assert_select "button[type=submit]", text: "선택 일괄 승인"
      assert_select "form", count: 1
    end
    assert_select "input[name='report_ids[]'][value=?][form=batch_approve_reports]", @report.id.to_s
    assert_select "form[action=?]", approve_teacher_review_path(@report) do
      assert_select "button[type=submit]", text: "승인"
    end
  end

  test "a student is forbidden from the review queue" do
    login_as @student
    get teacher_reviews_path
    assert_response :forbidden
  end

  test "a non-담임 teacher is forbidden from another classroom's report" do
    login_as @other_teacher
    get teacher_review_path(@report)
    assert_response :forbidden
  end

  test "update saves the teacher rubric adjustment and comment" do
    login_as @teacher
    patch teacher_review_path(@report), params: {
      report: { teacher_comment: "잘했어요",
                teacher_rubric: { content: 5, emotion: 4, life: 4, structure: 3, spelling: 4 } }
    }

    @report.reload
    assert_equal "잘했어요", @report.teacher_comment
    assert_equal 5, @report.teacher_rubric["content"]
  end

  test "approve marks the report reviewed and broadcasts to the student" do
    login_as @teacher

    broadcasts = capture_turbo_stream_broadcasts([ @student, :reports ]) do
      post approve_teacher_review_path(@report)
    end

    @report.reload
    assert @report.reviewed?
    assert_not_nil @report.reviewed_at
    assert_equal 1, broadcasts.size
    assert_equal "replace", broadcasts.first["action"]
  end

  test "approving a report grants the student's reading badge (approval fires the badge cascade)" do
    seed_badges!
    login_as @teacher

    assert_not_includes @student.badges.pluck(:key), "first"
    post approve_teacher_review_path(@report)

    assert_includes @student.badges.reload.pluck(:key), "first",
      "승인 시점에 first(독후감 1편) 뱃지가 부여돼야 한다"
  end


  test "batch_approve approves all selected reports" do
    other = Report.create!(user: @student, classroom: @classroom, book_title: "책2", ai_status: :done, reviewed: false, submitted_at: Time.current)
    login_as @teacher

    post batch_approve_teacher_reviews_path, params: { report_ids: [ @report.id, other.id ] }

    assert @report.reload.reviewed?
    assert other.reload.reviewed?
  end

  # --- report-review-gate: 교사 첨삭 텍스트 편집 + 승인 전 방송 억제 ---

  test "teacher review show exposes AI feedback text before approval (teacher-only view is not gated)" do
    @report.update!(rubric: { content: 4, emotion: 4, life: 4, structure: 4, spelling: 4,
      praise: [ "잘한 점 예시" ], fix: [ "보완할 점 예시" ],
      grow: [ { text: "성장 제안 예시", standard_code: "2국05-01" } ] })

    login_as @teacher
    get teacher_review_path(@report)
    assert_response :success
    assert_match "잘한 점 예시", response.body
    assert_match "보완할 점 예시", response.body
    assert_match "성장 제안 예시", response.body
  end

  # grow 는 항목별 고정 입력(text만 편집)이라 standard_code 는 위조 파라미터를 무시하고
  # 서버가 원본 rubric 의 코드로 재설정해야 한다(오정렬·위조 이중 방지).
  test "update saves teacher-edited feedback text and resets grow standard_code from the original rubric" do
    @report.update!(rubric: { content: 4, emotion: 4, life: 4, structure: 4, spelling: 4,
      praise: [ "AI 칭찬" ], fix: [ "AI 보완" ],
      grow: [ { text: "제안 원본", standard_code: "2국05-01" } ] })

    login_as @teacher
    patch teacher_review_path(@report), params: {
      report: {
        teacher_feedback: {
          praise: "교사 칭찬1\n교사 칭찬2",
          fix: "교사 보완",
          grow: { "0" => { text: "교사가 고친 제안", standard_code: "위조코드-999" } }
        }
      }
    }

    feedback = @report.reload.teacher_feedback.with_indifferent_access
    assert_equal [ "교사 칭찬1", "교사 칭찬2" ], feedback[:praise]
    assert_equal [ "교사 보완" ], feedback[:fix]
    assert_equal "교사가 고친 제안", feedback[:grow].first["text"]
    assert_equal "2국05-01", feedback[:grow].first["standard_code"],
      "성취기준 코드는 폼 위조값이 아니라 원본 rubric 기준으로 서버가 재설정해야 한다"
  end

  # 미승인(reviewed false) 편집은 학생에게 아직 안 보이므로 방송하지 않는다. 승인 후(reviewed
  # true) 정정은 학생이 이미 볼 수 있는 첨삭이므로 즉시 라이브 반영해야 한다.
  test "update broadcasts the report detail stream only once the report is already reviewed" do
    login_as @teacher

    assert_no_turbo_stream_broadcasts(@report) do
      patch teacher_review_path(@report), params: { report: { teacher_comment: "미승인 편집" } }
    end
    assert_not @report.reload.reviewed?

    post approve_teacher_review_path(@report)
    assert @report.reload.reviewed?

    assert_turbo_stream_broadcasts(@report) do
      patch teacher_review_path(@report), params: { report: { teacher_comment: "승인 후 편집" } }
    end
  end

  private
end
