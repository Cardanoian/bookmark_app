require "test_helper"

# P5.5 — 단계 학습 위저드 5단계: 단계 진행, 이탈 후 복귀(세션 복원), 완료 시 독후감 초안 연결.
class LearnWizardTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "위저드초등학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @student = User.create!(school: @school, classroom: @classroom, name: "위저드학생", password: "password")
  end

  test "index starts at step 1 and injects the achievement standard" do
    login_as @student
    get learn_index_path
    assert_response :success
    assert_select "h1", /단계 학습/
    assert_includes response.body, "[6국02-05]"
  end

  test "advancing moves through the five steps in order" do
    login_as @student

    post advance_learn_index_path, params: { step: 1, answer: "마당을 나온 암탉을 읽었어요." }
    assert_redirected_to learn_index_path
    follow_redirect!
    assert_includes response.body, "[6국05-03]" # 2단계 성취기준

    post advance_learn_index_path, params: { step: 2, answer: "잎싹이 알을 품는 이야기." }
    follow_redirect!
    assert_includes response.body, "[6국05-04]" # 3단계 성취기준
  end

  test "progress is restored after leaving and returning" do
    login_as @student
    post advance_learn_index_path, params: { step: 1, answer: "책 고르기 답" }
    post advance_learn_index_path, params: { step: 2, answer: "줄거리 답" }

    # 다른 화면에 다녀와도(이탈) 진행이 유지된다.
    get root_path
    get learn_index_path
    assert_response :success
    assert_includes response.body, "3단계"
    assert_includes response.body, "책 고르기 답" # 앞 단계 답안 요약 복원
  end

  # 진행은 세션 쿠키가 아니라 학생 행(LearnWizardProgress)에 둔다 — 로그아웃했다가(다른 기기) 다시 와도 잇는다.
  test "progress continues after logging in again" do
    login_as @student
    post advance_learn_index_path, params: { step: 1, answer: "책 고르기 답" }
    post advance_learn_index_path, params: { step: 2, answer: "줄거리 답" }
    delete session_path

    login_as @student
    get learn_index_path
    assert_includes response.body, "3단계"
    assert_includes response.body, "줄거리 답"
  end

  # 마치면 다섯 답을 '작성 중' 독후감(미제출 초안)으로 저장하고 그 편집 화면을 연다. 본문을 주소에
  # 싣지 않는다 — 예전에는 new 주소에 본문 전체를 실어 Puma 주소 한도(쿼리 10KB, 한글 약 1,100자)에 걸렸다.
  test "completing the wizard saves the five steps as a draft and opens its edit screen" do
    login_as @student
    answers = {
      1 => "마당을 나온 암탉\n알을 품고 싶은 암탉 이야기라서 골랐어요.",
      2 => "잎싹의 줄거리.",
      3 => "가장 인상 깊은 장면.",
      4 => "내 생각과 느낌.",
      5 => "내 삶과의 연결."
    }
    answers.first(4).each { |step, answer| post advance_learn_index_path, params: { step: step, answer: answer } }

    assert_difference -> { @student.reports.count }, 1 do
      post advance_learn_index_path, params: { step: 5, answer: answers[5] }
    end
    draft = @student.reports.order(:id).last
    assert_redirected_to edit_report_path(draft)

    assert draft.draft?, "제출하지 않은 초안이다(교사 큐·AI 첨삭 대상 아님)"
    assert draft.keyboard?
    assert_equal @classroom, draft.classroom
    assert_equal "마당을 나온 암탉", draft.book_title
    answers.each_value { |answer| assert_includes draft.body, answer }
    assert_includes draft.body, "[삶과 연결] 내 삶과의 연결."
    assert_no_enqueued_jobs only: AiReviewJob

    follow_redirect!
    assert_response :success
    assert_select "textarea", text: /내 삶과의 연결\./
    # 위저드 진행은 완료 후 초기화된다.
    get learn_index_path
    assert_includes response.body, "1단계"
    assert_not_includes response.body, "잎싹의 줄거리."
  end

  # 답을 길게 써도 실패하지 않는다. 세션 쿠키(4KB)에 쌓던 때는 합쳐서 한글 약 750자면 CookieOverflow(500)였다.
  test "long answers neither overflow the cookie nor get lost" do
    login_as @student
    answers = (1..5).to_h { |step| [ step, "#{step}단계 긴 답 " + ("가나다라마바사" * 115) ] } # 단계마다 약 800자

    answers.each { |step, answer| post advance_learn_index_path, params: { step: step, answer: answer } }

    draft = @student.reports.order(:id).last
    assert_redirected_to edit_report_path(draft)
    answers.each_value { |answer| assert_includes draft.body, answer }
  end

  # 1단계 첫 줄(책 제목)이 비면 초안을 만들 수 없다(책 참조 검증). 1단계로 돌려보내고 답은 지우지 않는다.
  test "a blank book title sends the student back to step 1 with the answers kept" do
    login_as @student
    post advance_learn_index_path, params: { step: 1, answer: "   " }
    (2..4).each { |step| post advance_learn_index_path, params: { step: step, answer: "#{step}단계 답" } }

    assert_no_difference -> { Report.count } do
      post advance_learn_index_path, params: { step: 5, answer: "5단계 답" }
    end
    assert_redirected_to learn_index_path
    follow_redirect!
    assert_includes response.body, "1단계"
    assert_match "책 제목", flash[:alert]
    assert_includes response.body, "5단계 답", "앞서 쓴 답은 남는다"
  end

  # 챌린지에 참여한 직후의 첫 독후감에 그 챌린지를 잇는다(ReportsController#create 와 같은 세션 표 — 챌린지
  # 순위가 이 연결로 센다). 예전에는 단계 학습 → 새 글 화면의 첫 저장이 표를 소비했다.
  test "the draft is linked to the challenge the student just joined" do
    challenge = Challenge.create!(title: "단계 학습 챌린지", scope: :global)
    login_as @student
    post join_challenge_path(challenge)

    (1..5).each { |step| post advance_learn_index_path, params: { step: step, answer: "#{step}단계 답" } }

    assert_equal challenge.id, @student.reports.order(:id).last.challenge_id
    assert_nil session[:active_challenge_id], "표는 한 번만 쓴다"
  end

  # 독후감은 학생만 쓴다(ReportPolicy#create?). 예전에도 담임이 마치면 새 글 화면에서 403 이었다.
  test "a teacher finishing the wizard gets no report" do
    teacher = User.create!(school: @school, name: "위저드담임", role: :teacher, password: "password")
    login_as teacher
    (1..4).each { |step| post advance_learn_index_path, params: { step: step, answer: "#{step}단계 답" } }

    assert_no_difference -> { Report.count } do
      post advance_learn_index_path, params: { step: 5, answer: "5단계 답" }
    end
    assert_response :forbidden
  end

  test "wizard requires login" do
    get learn_index_path
    assert_redirected_to new_session_path
  end

  # 성취기준은 학생 학년군 것만 보여 준다 — 1~4학년에게 5~6학년 코드를 보이지 않는다.
  test "shows the achievement standard of the student's own grade band" do
    { 2 => %w[[2국02-05] [2국02-03]], 3 => %w[[4국02-06] [4국02-02]] }.each do |grade, (step1, step2)|
      classroom = Classroom.create!(school: @school, grade: grade, class_no: 9)
      student = User.create!(school: @school, classroom: classroom, name: "위저드#{grade}학년", password: "password")
      login_as student

      get learn_index_path
      assert_includes response.body, step1
      assert_not_includes response.body, "[6국", "#{grade}학년에게 5~6학년 성취기준을 보이지 않는다"

      post advance_learn_index_path, params: { step: 1, answer: "책 고르기 답" }
      follow_redirect!
      assert_includes response.body, step2
      delete session_path
    end
  end

  test "a student without a classroom sees the lowest grade band, not 5~6" do
    student = User.create!(school: @school, name: "학급없는학생", password: "password")
    login_as student

    get learn_index_path
    assert_includes response.body, "[2국02-05]"
    assert_not_includes response.body, "[6국"
  end

  # 단계마다 세 학년군 코드가 모두 있고, 각 코드가 그 학년군 첨삭 목록(고시 원문) 안에 있다.
  test "every step has a standard from each band's own curriculum list" do
    LearnController::STEPS.each do |step|
      assert_equal %i[g12 g34 g56], step[:codes].keys
      step[:codes].each do |band, code|
        allowed = ReadingDomain::CURRICULUM_STANDARDS_BY_BAND.fetch(band).values.flatten(1).map(&:first)
        assert_includes allowed, code, "#{step[:title]} #{band}"
      end
    end
  end
end
