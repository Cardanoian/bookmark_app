require "test_helper"

# 전국 공유 문제은행 UGC(게임 재구성 Phase 3 §3.5·§4). 학생 출제 → 담임 검토·수정 → 승인 시
# system·global·band 풀 퀴즈로 물질화(전국 편입) → resolve 풀 등장. 반려는 미편입. 크로스-학급 차단.
# 총괄관리자 에스컬레이션(전국 신고 콘텐츠 숨김/복원/삭제).
class QuizContributionsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @school = School.create!(name: "기여통합초")
    @room_a = Classroom.create!(school: @school, grade: 5, class_no: 1) # grade5 → g56
    @room_b = Classroom.create!(school: @school, grade: 5, class_no: 2)
    @teacher_a = User.create!(school: @school, classroom: @room_a, name: "담임A", role: :teacher, password: "password")
    Classroom.find(@room_a.id).update!(teacher_id: @teacher_a.id)
    @teacher_b = User.create!(school: @school, classroom: @room_b, name: "담임B", role: :teacher, password: "password")
    Classroom.find(@room_b.id).update!(teacher_id: @teacher_b.id)
    @student = User.create!(school: @school, classroom: @room_a, name: "출제학생", password: "password")
    @book = Book.create!(title: "기여통합책", author: "김작가", category: :recommended)
    @superadmin = User.create!(school: nil, classroom: nil, name: "총괄", role: :superadmin,
                               email: "super@test.local", password: "password")
  end

  def mcq_params
    { quiz_contribution: { book_id: @book.id, content_axis: "mcq", prompt: "주인공은 누구인가요?",
                           choices: %w[가 나 다 라], answer_number: "2", explanation: "해설이에요." } }
  end

  def ready_pool(band: "g56", axis: "mcq")
    Quiz.where(origin: :system, generation_status: :ready, reported: false,
               book_id: @book.id, band: band, content_axis: axis)
  end

  # ── 학생 출제 → pending 생성, 아직 아무에게도 안 보임 ──────────────────────
  test "a student contribution creates a pending row and materializes no pool quiz" do
    login_as @student
    assert_no_difference -> { Quiz.count } do
      assert_difference -> { QuizContribution.count }, 1 do
        post quiz_contributions_path, params: mcq_params
      end
    end
    contribution = QuizContribution.last
    assert contribution.pending?
    assert_equal @student.id, contribution.user_id
    assert_equal @room_a.id, contribution.classroom_id, "학급은 서버가 확정(위조 불가)"
    assert_equal "g56", contribution.band, "밴드는 작성자 학년에서 기본 파생"
    assert_equal 1, contribution.payload_hash[:answer_index], "1-based 입력이 0-based 로 저장"
    assert_redirected_to reading_activity_path(book_id: @book.id)
  end

  test "an invalid contribution is rejected without creating a row" do
    login_as @student
    assert_no_difference -> { QuizContribution.count } do
      post quiz_contributions_path, params: { quiz_contribution: { book_id: @book.id, content_axis: "mcq",
        prompt: "질문", choices: %w[가 나], answer_number: "1" } }
    end
    assert_response :unprocessable_entity
  end

  test "a teacher cannot create a contribution (student-only)" do
    login_as @teacher_a
    assert_no_difference -> { QuizContribution.count } do
      post quiz_contributions_path, params: mcq_params
    end
    assert_response :forbidden
  end

  # ── 교사 검토: 담임만 자기 학급 학생 pending 열람 ─────────────────────────
  test "the homeroom teacher sees only their own classroom students' pending contributions" do
    mine = create_pending(@student)
    outsider_student = User.create!(school: @school, classroom: @room_b, name: "타반학생", password: "password")
    theirs = create_pending(outsider_student)

    login_as @teacher_a
    get teacher_quiz_contributions_path
    assert_response :success
    assert_includes response.body, mine.payload_hash[:prompt]
    refute_includes response.body, theirs.payload_hash[:prompt], "타 학급 학생 기여는 큐에 안 뜬다"
  end

  test "approving a cross-classroom student's contribution is forbidden" do
    contribution = create_pending(@student) # room_a student
    login_as @teacher_b                      # 담임 of room_b
    post approve_teacher_quiz_contribution_path(contribution)
    assert_response :forbidden
    assert contribution.reload.pending?, "크로스-학급 승인은 403 — 편입되지 않는다"
  end

  # ── 승인 → system·global·band 풀 퀴즈 + contributed 문항 물질화 ────────────
  # 승인은 이제 형제 폼의 독립 button_to(필드 없음)라 **먼저 저장(update)한 뒤 승인**하는 2스텝으로
  # 교사 수정 내용을 반영한다(BLOCKER 수정 — 승인 요청 자체는 편집 파라미터를 보내지 않는다).
  test "a teacher edit (update) followed by approve materializes the edited content into the pool" do
    contribution = create_pending(@student)
    login_as @teacher_a

    patch teacher_quiz_contribution_path(contribution),
      params: { quiz_contribution: { band: "g56", prompt: "수정된 질문?", choices: %w[하나 둘 셋 넷],
                                     answer_number: "3", explanation: "수정 해설" } }
    assert_redirected_to teacher_quiz_contributions_path
    assert_equal "수정된 질문?", contribution.reload.payload_hash[:prompt], "저장 단계에서 수정 내용이 먼저 반영된다"

    assert_difference -> { ready_pool.count }, 1 do
      post approve_teacher_quiz_contribution_path(contribution) # 필드 없는 독립 폼 — 저장된 현재 페이로드를 물질화
    end
    assert_redirected_to teacher_quiz_contributions_path
    assert contribution.reload.approved?
    assert_equal @teacher_a.id, contribution.reviewed_by_id

    quiz = ready_pool.order(:id).last
    assert_equal "system", quiz.origin
    assert_equal "global", quiz.scope
    assert quiz.published?
    assert_equal "g56", quiz.band
    question = quiz.quiz_questions.first
    assert_equal "contributed", question.source, "기여 문항은 source: contributed"
    assert_equal "수정된 질문?", question.prompt, "저장 단계의 교사 수정 내용이 승인 시 그대로 물질화된다"
    assert_equal 2, question.answer_index, "3번(1-based) → index 2"
  end

  # approve 요청 자체가 (독립 폼이라) 편집 파라미터를 보내지 않아도 원래 학생 페이로드가
  # 그대로 물질화되는지(수정 없이 바로 승인하는 1스텝 경로) 확인한다.
  test "approving without a prior edit materializes the original student payload as-is" do
    contribution = create_pending(@student)
    original_prompt = contribution.payload_hash[:prompt]
    login_as @teacher_a

    assert_difference -> { ready_pool.count }, 1 do
      post approve_teacher_quiz_contribution_path(contribution)
    end
    assert contribution.reload.approved?

    question = ready_pool.order(:id).last.quiz_questions.first
    assert_equal original_prompt, question.prompt, "수정 없이 승인하면 원래 학생 페이로드가 그대로 물질화된다"
  end

  test "the materialized contribution can be served by the resolver pool" do
    contribution = create_pending(@student)
    login_as @teacher_a
    post approve_teacher_quiz_contribution_path(contribution)

    contributed = ready_pool.detect { |q| q.quiz_questions.any?(&:contributed?) }
    assert contributed, "승인 기여가 준비 풀에 있다"

    # sampler seam 으로 기여 세트를 고르면 resolve 가 그 세트를 서빙한다(세트 단위 랜덤 출제의 후보).
    served = Games::ContentProvider.resolve(book: @book, surface: "quiz", user: @student,
      sampler: ->(candidates) { candidates.detect { |q| q.quiz_questions.any?(&:contributed?) } || candidates.first })
    assert served.quiz_questions.any?(&:contributed?), "resolve 가 기여 세트를 출제할 수 있다"
  end

  # ── BLOCKER 회귀: 렌더된 큐 화면의 승인·반려 컨트롤이 오염 없는 독립 POST 폼으로 렌더되는지 ──
  # (수정 폼이 form_with method: :patch 로 열려 있고 그 안에서 승인을 formaction: approve_path,
  # formmethod: "post" 로 보내면, 브라우저가 히든 _method=patch 를 approve 제출에도 함께 실어
  # Rack::MethodOverride 가 POST 를 PATCH 로 승격시켜 라우트 없음(404) 났었다. 반려 button_to 가
  # 수정 폼 안에 중첩된 것도 불법 중첩 폼이라 파서가 내부 폼을 버리고 update 로 흡수했었다.
  # 승인·반려는 수정 폼 밖의 독립 형제 폼이어야 한다.)
  test "the rendered review queue exposes approve/reject as standalone POST forms, not nested inside the edit form" do
    contribution = create_pending(@student)
    login_as @teacher_a

    get teacher_quiz_contributions_path
    assert_response :success

    doc = Nokogiri::HTML::Document.parse(response.body)
    forms = doc.css("form")

    update_form = forms.detect do |f|
      f["action"].to_s == teacher_quiz_contribution_path(contribution) && f.at_css("input[name='_method'][value='patch']")
    end
    approve_form = forms.detect { |f| f["action"].to_s == approve_teacher_quiz_contribution_path(contribution) }
    reject_form = forms.detect { |f| f["action"].to_s == reject_teacher_quiz_contribution_path(contribution) }

    assert update_form, "수정 저장 폼(PATCH update)이 렌더된다"
    assert approve_form, "승인 폼이 독립적으로 렌더된다"
    assert reject_form, "반려 폼이 독립적으로 렌더된다"

    # 승인·반려 폼은 method="post"만 갖고(native POST) _method 오버라이드 히든 필드가 없어야 한다 —
    # 있으면 Rack::MethodOverride 가 POST 를 그 값으로 승격시켜 버린다(BLOCKER 재발 감지).
    assert_equal "post", approve_form["method"].to_s.downcase
    assert_nil approve_form.at_css("input[name='_method']"), "승인 폼에 _method 오버라이드가 있으면 안 된다(POST→PATCH 승격 방지)"
    assert_equal "post", reject_form["method"].to_s.downcase
    assert_nil reject_form.at_css("input[name='_method']"), "반려 폼에 _method 오버라이드가 있으면 안 된다"

    # 승인·반려 폼이 수정 폼 **안에 중첩**되지 않았는지(불법 중첩 폼은 파서가 내부 폼을 버리고
    # 바깥 폼[update]으로 흡수한다) — 형제 관계(같은 부모의 자식들)여야 한다.
    assert_not update_form.css("form").include?(approve_form), "승인 폼이 수정 폼 안에 중첩되지 않는다"
    assert_not update_form.css("form").include?(reject_form), "반려 폼이 수정 폼 안에 중첩되지 않는다"
  end

  # 렌더된 승인 폼의 실제 action/method 로 그대로 제출(브라우저가 그 폼을 제출했을 때와 동일 —
  # method="post"·_method 없음)했을 때 승인·물질화가 성립하는지 렌더 경로로 증명한다.
  test "submitting the rendered approve form's exact action+method approves and materializes" do
    contribution = create_pending(@student)
    login_as @teacher_a

    get teacher_quiz_contributions_path
    doc = Nokogiri::HTML::Document.parse(response.body)
    approve_form = doc.css("form").detect { |f| f["action"].to_s == approve_teacher_quiz_contribution_path(contribution) }
    assert approve_form, "승인 폼을 찾을 수 있어야 렌더 경로 제출을 검증할 수 있다"
    assert_equal "post", approve_form["method"].to_s.downcase

    assert_difference -> { ready_pool.count }, 1 do
      post approve_form["action"] # 렌더된 폼 그대로 제출(추가 히든 _method 없음 — native POST)
    end
    assert contribution.reload.approved?
  end

  # 렌더된 반려 폼의 실제 action/method 로 제출했을 때 반려·미편입이 성립하는지(update 로 흡수되지
  # 않는지) 렌더 경로로 증명한다.
  test "submitting the rendered reject form's exact action+method rejects without materializing" do
    contribution = create_pending(@student)
    login_as @teacher_a

    get teacher_quiz_contributions_path
    doc = Nokogiri::HTML::Document.parse(response.body)
    reject_form = doc.css("form").detect { |f| f["action"].to_s == reject_teacher_quiz_contribution_path(contribution) }
    assert reject_form, "반려 폼을 찾을 수 있어야 렌더 경로 제출을 검증할 수 있다"
    assert_equal "post", reject_form["method"].to_s.downcase

    assert_no_difference -> { ready_pool.count } do
      post reject_form["action"]
    end
    assert contribution.reload.rejected?
  end

  test "rejecting does not materialize any pool quiz" do
    contribution = create_pending(@student)
    login_as @teacher_a
    assert_no_difference -> { ready_pool.count } do
      post reject_teacher_quiz_contribution_path(contribution)
    end
    assert contribution.reload.rejected?
  end

  # ── 전국성: 다른 학교 학생도 승인 기여를 (같은 밴드) 플레이 풀에서 만난다 ────
  test "a student at another school meets the approved contribution in the same-band pool" do
    contribution = create_pending(@student)
    login_as @teacher_a
    post approve_teacher_quiz_contribution_path(contribution)
    logout

    other_school = School.create!(name: "다른학교초")
    other_room = Classroom.create!(school: other_school, grade: 6, class_no: 1) # grade6 → g56
    other_student = User.create!(school: other_school, classroom: other_room, name: "타교학생", password: "password")

    contributed = ready_pool.detect { |q| q.quiz_questions.any?(&:contributed?) }
    assert QuizPolicy.new(other_student, contributed).show?, "다른 학교 g56 학생도 밴드 일치로 플레이 가능(전국 공유)"

    login_as other_student
    get games_quiz_play_path(book_id: @book.id)
    assert_response :success, "타 학교 학생도 이 책 mcq 를 플레이할 수 있다(system within_band 전국)"
  end

  # ── 총괄관리자 에스컬레이션: 신고된 전국 풀 퀴즈 숨김/복원, 경계(총괄만) ────
  test "a superadmin can hide and restore a reported nationwide pool quiz" do
    contribution = create_pending(@student)
    Games::ContributionPublisher.publish!(contribution.tap { |c| c.update!(status: :approved) })
    quiz = ready_pool.last
    quiz.update!(reported: true, reports_count: 2) # 전국 신고 상태

    login_as @superadmin
    get admin_game_contents_path
    assert_response :success
    assert_includes response.body, @book.title

    post restore_admin_game_content_path(quiz)
    assert_not quiz.reload.reported?, "총괄이 복원하면 다시 플레이 풀에 노출"

    post hide_admin_game_content_path(quiz)
    assert quiz.reload.reported?, "총괄이 영구 숨김"
  end

  test "a superadmin can destroy a nationwide pool quiz" do
    contribution = create_pending(@student)
    Games::ContributionPublisher.publish!(contribution.tap { |c| c.update!(status: :approved) })
    quiz = ready_pool.last

    login_as @superadmin
    assert_difference -> { Quiz.count }, -1 do
      delete admin_game_content_path(quiz)
    end
  end

  test "a non-superadmin cannot reach the game content escalation queue" do
    login_as @teacher_a
    get admin_game_contents_path
    assert_response :forbidden
  end

  private

  def create_pending(user, axis: :mcq)
    payload =
      if axis == :mcq
        { "prompt" => "#{user.name} 질문?", "choices" => %w[가 나 다 라], "answer_index" => 1, "explanation" => "해설" }
      else
        { "answer" => "잎싹", "hints" => [ "동물", "두 글자" ], "explanation" => "" }
      end
    QuizContribution.create!(user: user, book: @book, classroom: user.classroom,
                             content_axis: axis, band: :g56, payload: payload)
  end

  def logout
    delete session_path
  end
end
