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
    # 둘 다 **지금 제출의 첨삭이 완성된** 글이다(review_ready_attributes — 버전 컬럼 기본값에 기대지 않는다).
    @report = Report.create!(
      user: @student, classroom: @classroom, book_title: "책", body: "본문",
      avg: 3.0, level: "B", reviewed: false, **review_ready_attributes
    )
    @reviewed_report = Report.create!(
      user: @student, classroom: @classroom, book_title: "이미검토한책", body: "검토완료 본문",
      avg: 4.0, level: "A", reviewed: true, reviewed_at: 1.day.ago, **review_ready_attributes
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

  # 검토완료 글이 목록에 노출되면서 id 를 알아내기 쉬워졌다. batch_approve 는 이미 승인된 글을 다시 승인
  # 캐스케이드에 태우지 않아야 한다(Report#approve! 의 조건부 전이 — reviewed = false 일 때만).
  test "batch_approve ignores already reviewed reports" do
    original_reviewed_at = @reviewed_report.reviewed_at
    login_as @teacher

    post batch_approve_teacher_reviews_path, params: batch_params(@report, @reviewed_report)

    assert @report.reload.reviewed?
    assert_equal original_reviewed_at.to_i, @reviewed_report.reload.reviewed_at.to_i,
      "이미 승인한 독후감은 batch_approve 로 재승인되지 않아야 한다"
    assert_match "독후감 1편을 승인했어요. 1편은", flash[:notice], "승인한 건수와 제외한 건수를 따로 알린다"
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
      review_version: @report.review_version,
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
      post approve_teacher_review_path(@report), params: { review_version: @report.review_version }
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
    post approve_teacher_review_path(@report), params: { review_version: @report.review_version }

    assert_includes @student.badges.reload.pluck(:key), "first",
      "승인 시점에 first(독후감 1편) 뱃지가 부여돼야 한다"
  end


  # F3(BUG_FIX_PLAN §5): 첨삭이 만들어지기 전에는 승인할 수 없다.
  # 재현: AI 처리 중인 글이 승인되고, 그 뒤 첨삭이 저장되는 순간 교사가 읽지 않은 채 학생에게 공개됐다 —
  # approve? 가 ai_status 를 보지 않았고 feedback_visible? 는 reviewed? && rubric.present? 였다.
  test "AI 첨삭이 끝나기 전의 글은 승인되지 않고, 나중에 생긴 첨삭도 확인 없이 공개되지 않는다 (F3)" do
    waiting = Report.create!(user: @student, classroom: @classroom, book_title: "대기책",
                             body: "나는 이 책을 읽고 우리의 삶을 생각했다. 감동을 느꼈다.",
                             ai_status: :pending, submitted_at: Time.current)
    waiting.update_columns(review_version: 1) # 제출된 글(첨삭 대기)
    login_as @teacher

    post approve_teacher_review_path(waiting), params: { review_version: 1 }
    assert_not waiting.reload.reviewed?, "첨삭이 만들어지기 전에는 승인되지 않는다"
    assert_match "아직 첨삭이 준비되지 않은", flash[:alert]

    perform_ai_review(waiting)

    waiting.reload
    assert waiting.done?
    assert_not waiting.feedback_visible?, "교사가 확인하지 않은 첨삭은 학생에게 공개되지 않는다"

    post approve_teacher_review_path(waiting), params: { review_version: 1 }
    assert waiting.reload.feedback_visible?, "완성된 첨삭을 확인하고 승인한 뒤에 공개된다"
  end

  # 준비 중·처리 중·실패·초안은 단건·일괄 어느 쪽으로도 승인되지 않는다(직접 요청 포함). 보상·공개도 없다.
  test "준비 중·처리 중·실패·초안은 단건으로도 일괄로도 승인되지 않는다 (F3)" do
    seed_badges!
    not_ready = {
      pending: { ai_status: :pending, submitted_at: Time.current, review_version: 1 },
      processing: { ai_status: :processing, submitted_at: Time.current, review_version: 1 },
      failed: { ai_status: :failed, submitted_at: Time.current, review_version: 1 },
      # 고쳐 다시 낸 글: 이전 제출의 루브릭·done 이 남아 있지만 새 버전의 첨삭은 아직이다.
      resubmitted: { ai_status: :pending, submitted_at: Time.current, review_version: 2, completed_review_version: 1,
                     rubric: REVIEW_READY_RUBRIC.deep_dup },
      draft: { ai_status: :done, rubric: REVIEW_READY_RUBRIC.deep_dup } # 미제출 초안(버전 0)
    }.transform_values { |attrs| Report.create!(user: @student, classroom: @classroom, book_title: "준비중", body: "본문", **attrs) }
    Report.where(id: [ @report.id, @reviewed_report.id ]).delete_all # 이 학생의 승인 가능 글을 치워 보상 여부를 본다
    login_as @teacher

    not_ready.each_value do |report|
      post approve_teacher_review_path(report), params: { review_version: report.review_version }
    end
    post batch_approve_teacher_reviews_path, params: batch_params(*not_ready.values)

    not_ready.each do |state, report|
      assert_not report.reload.reviewed?, "#{state} 상태는 승인되지 않는다"
      assert_not report.feedback_visible?
    end
    assert_match "승인한 독후감이 없어요", flash[:notice]
    assert_empty @student.badges.reload.pluck(:key), "승인 캐스케이드(뱃지)가 돌지 않는다"
  end

  # 준비 중인 글은 목록·상세에 승인 컨트롤도, 이전 제출의 첨삭·등급도 보이지 않는다.
  test "준비 중·실패한 글은 승인 컨트롤 없이 상태만 보인다 (F3)" do
    resubmitted = Report.create!(user: @student, classroom: @classroom, book_title: "다시낸책", body: "새 본문",
                                 avg: 4.5, level: "A", **review_ready_attributes(ai_status: :pending, review_version: 2))
    failed = Report.create!(user: @student, classroom: @classroom, book_title: "실패한책", body: "본문",
                            ai_status: :failed, submitted_at: 1.hour.ago, review_version: 1)
    login_as @teacher

    get teacher_reviews_path
    [ resubmitted, failed ].each do |report|
      assert_select "article#report_#{report.id}" do
        assert_select "input[name='report_ids[]']", count: 0
        assert_select "form[action=?]", approve_teacher_review_path(report), count: 0
      end
    end
    assert_select "article#report_#{resubmitted.id}", text: /첨삭 준비 중/
    assert_select "article#report_#{resubmitted.id}", { text: /평균 4.5/, count: 0 }, "이전 제출의 평균을 보이지 않는다"
    assert_select "article#report_#{failed.id}", text: /첨삭 실패/

    get teacher_review_path(resubmitted)
    assert_select "form[action=?]", approve_teacher_review_path(resubmitted), count: 0
    assert_select "form[action=?][method=post] input[name=_method][value=patch]", teacher_review_path(resubmitted), count: 0
    assert_no_match "줄거리를 차례대로 잘 정리했어요.", response.body, "이전 제출의 첨삭을 보이지 않는다"
    assert_match "AI 첨삭을 준비하고 있어요", response.body

    get teacher_review_path(failed)
    assert_match "AI 첨삭에 실패했어요", response.body
    assert_select "form[action=?]", retry_review_report_path(failed), { count: 1 }, "실패한 글은 같은 버전으로 다시 요청할 수 있다"
  end

  # 화면을 연 뒤 학생이 다시 냈다 — 옛 화면의 승인·저장은 최신 글에 닿지 않는다. 버전이 없는 요청도 같다.
  test "오래된 화면의 승인·교사 편집과 버전 없는 요청은 최신 글을 바꾸지 않는다 (F3)" do
    login_as @teacher
    get teacher_review_path(@report)
    assert_select "form[action=?] input[name=review_version][value='1']", approve_teacher_review_path(@report)
    assert_select "input#review_form_version[name=review_version][value='1']"

    # 그사이 학생이 고쳐 다시 냈고 새 첨삭까지 끝났다.
    @report.record_submission!
    perform_ai_review(@report)
    assert @report.reload.review_ready?

    stale_edit = { report: { teacher_comment: "옛 글을 보고 쓴 코멘트", teacher_feedback: { praise: "옛 칭찬", fix: "" } } }
    [ { review_version: 1 }, {} ].each do |seen|
      post approve_teacher_review_path(@report), params: seen
      assert_redirected_to teacher_review_path(@report)
      patch teacher_review_path(@report), params: seen.merge(stale_edit)
      assert_match "학생이 그사이 글을 다시 냈어요", flash[:alert]
    end
    post batch_approve_teacher_reviews_path, params: { report_ids: [ @report.id ], review_versions: { @report.id => 1 } }
    post batch_approve_teacher_reviews_path, params: { report_ids: [ @report.id ] } # 버전 없는 일괄 승인

    @report.reload
    assert_not @report.reviewed?, "새 제출은 미승인으로 남는다"
    assert_nil @report.teacher_comment
    assert_nil @report.teacher_feedback, "옛 편집본이 최신 글에 덮이지 않는다"

    post approve_teacher_review_path(@report), params: { review_version: 2 }
    assert @report.reload.reviewed?, "최신 화면에서 확인한 버전은 승인된다"
  end

  # 같은 버전의 재승인은 성공한 기존 결과로 안내하되 승인 시각·보상·방송을 다시 일으키지 않는다.
  test "같은 버전을 다시 승인해도 승인 시각과 방송이 되풀이되지 않는다 (F3)" do
    login_as @teacher
    post approve_teacher_review_path(@report), params: { review_version: 1 }
    approved_at = @report.reload.reviewed_at

    # assert_no_turbo_stream_broadcasts 는 테스트 시작부터의 방송을 모두 세므로(첫 승인 포함) 새 방송만 잡는다.
    rebroadcasts = travel 1.minute do
      capture_turbo_stream_broadcasts([ @student, :reports ]) do
        post approve_teacher_review_path(@report), params: { review_version: 1 }
      end
    end
    assert_empty rebroadcasts, "재승인은 학생 화면 방송을 다시 일으키지 않는다"

    assert_redirected_to teacher_reviews_path
    assert_match "이미 승인했어요", flash[:notice]
    assert_equal approved_at, @report.reload.reviewed_at
  end

  # 다른 반 글은 일괄 승인의 제외 건수에도 세지 않는다(그런 글이 있는지 알리지 않는다).
  test "batch_approve 는 권한 밖 글을 승인하지도 세지도 않는다 (F3)" do
    foreign = Report.create!(user: User.create!(school: @school, classroom: @other_classroom, name: "다른반학생", password: "password"),
                             classroom: @other_classroom, book_title: "다른반책", **review_ready_attributes)
    login_as @teacher

    post batch_approve_teacher_reviews_path, params: batch_params(@report, foreign)

    assert_not foreign.reload.reviewed?
    assert_equal "독후감 1편을 승인했어요.", flash[:notice]
  end

  test "batch_approve approves all selected reports" do
    other = Report.create!(user: @student, classroom: @classroom, book_title: "책2", reviewed: false, **review_ready_attributes)
    login_as @teacher

    post batch_approve_teacher_reviews_path, params: batch_params(@report, other)

    assert @report.reload.reviewed?
    assert other.reload.reviewed?
    assert_equal "독후감 2편을 승인했어요.", flash[:notice]
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

  test "teacher feedback textareas have matching sizes and accessible growth labels" do
    @report.update!(rubric: { content: 4, emotion: 4, life: 4, structure: 4, spelling: 4,
      praise: [ "AI 칭찬" ], fix: [ "AI 보완" ],
      grow: [ { text: "첫 제안", standard_code: "2국05-01" },
              { text: "둘째 제안", standard_code: "2국05-02" } ] })

    login_as @teacher
    get teacher_review_path(@report)

    assert_response :success
    assert_select "textarea.form-textarea[rows='3']", count: 5
    assert_select "fieldset" do
      assert_select "legend", text: "성장 제안"
      2.times do |index|
        input_id = "report_teacher_feedback_grow_#{index}_text"
        standard_id = "#{input_id}_standard"
        assert_select "label[for=?]", input_id, text: "성장 제안 #{index + 1}"
        assert_select "textarea##{input_id}[aria-describedby=?]", standard_id
        assert_select "p##{standard_id}.form-hint", text: /성취기준:/
      end
    end
  end

  # grow 는 항목별 고정 입력(text만 편집)이라 standard_code 는 위조 파라미터를 무시하고
  # 서버가 원본 rubric 의 코드로 재설정해야 한다(오정렬·위조 이중 방지).
  test "update saves teacher-edited feedback text and resets grow standard_code from the original rubric" do
    @report.update!(rubric: { content: 4, emotion: 4, life: 4, structure: 4, spelling: 4,
      praise: [ "AI 칭찬" ], fix: [ "AI 보완" ],
      grow: [ { text: "제안 원본", standard_code: "2국05-01" } ] })

    login_as @teacher
    patch teacher_review_path(@report), params: {
      review_version: @report.review_version,
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
      patch teacher_review_path(@report), params: { review_version: 1, report: { teacher_comment: "미승인 편집" } }
    end
    assert_not @report.reload.reviewed?

    post approve_teacher_review_path(@report), params: { review_version: @report.review_version }
    assert @report.reload.reviewed?

    assert_turbo_stream_broadcasts(@report) do
      patch teacher_review_path(@report), params: { review_version: 1, report: { teacher_comment: "승인 후 편집" } }
    end
  end

  private

  # 일괄 승인 폼이 보내는 모양: 선택한 글 id + 그 행에 보이던 제출 버전.
  def batch_params(*reports)
    { report_ids: reports.map(&:id), review_versions: reports.to_h { |report| [ report.id, report.review_version ] } }
  end
end
