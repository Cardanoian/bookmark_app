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

  # --- 고른 책 이어받기(2026-09-16 진입점 추가) ---
  # 쓰기 방식 고르는 화면에서 책을 고르고 들어오면 위저드가 그 책을 그대로 쓴다 — 1단계에서 책을 다시
  # 묻고 그 답을 버리면 책 고르기가 헛일이 된다.
  test "the wizard carries a book chosen before entering" do
    book = Book.create!(title: "위저드 고른 책", author: "지은이", isbn: TestBookIsbn.next)
    login_as @student

    get learn_index_path(report: { book_id: book.id, book_title: book.title })
    assert_response :success
    assert_includes response.body, "고른 책"
    assert_includes response.body, book.title

    (1..5).each do |step|
      post advance_learn_index_path,
           params: { step: step, answer: "#{step}단계 답", report: { book_id: book.id, book_title: book.title } }
    end

    draft = @student.reports.order(:id).last
    assert_equal book.id, draft.book_id, "고른 책이 초안에 이어진다"
    assert_equal book.title, draft.book_title
    assert_includes draft.body, "1단계 답", "단계 답은 그대로 본문이 된다"
  end

  # 위조·없는 book_id 는 무시하고 제목만 쓴다(ReportsController#resolved_book_id 와 같은 규약).
  test "a forged book id is ignored while the typed title is kept" do
    login_as @student

    (1..5).each do |step|
      post advance_learn_index_path,
           params: { step: step, answer: "#{step}단계 답", report: { book_id: 999_999, book_title: "직접 적은 책" } }
    end

    draft = @student.reports.order(:id).last
    assert_nil draft.book_id
    assert_equal "직접 적은 책", draft.book_title
  end

  # 진행 행에 적어 둔 책이 그사이 카탈로그에서 사라질 수 있다(관리자 정리·중복 병합). 마칠 때 다시 확인해
  # 없어진 책은 잇지 않는다 — 없는 id 로 저장하면 초안 만들기 자체가 실패해 다섯 답이 갇힌다.
  test "a book deleted while the wizard is in progress is dropped at completion" do
    book = Book.create!(title: "사라질 책", author: "지은이", isbn: TestBookIsbn.next)
    login_as @student

    (1..4).each do |step|
      post advance_learn_index_path,
           params: { step: step, answer: "#{step}단계 답", report: { book_id: book.id, book_title: book.title } }
    end
    book.destroy!

    post advance_learn_index_path, params: { step: 5, answer: "5단계 답" }

    draft = @student.reports.order(:id).last
    assert_nil draft.book_id
    assert_equal "사라질 책", draft.book_title, "제목은 답과 함께 남는다"
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

  # 챌린지에 참여한 뒤 단계 학습으로 쓴 글도 그 챌린지 순위에 센다 — 단, **낸 뒤에** 센다.
  # 2026-09-16 에 참여 세션 표를 걷어내고 참여 원장의 기간으로 세면서, 위저드가 만든 초안에 challenge_id 를
  # 다는 일도 없어졌다(예전에는 표를 한 번만 써서 참여당 한 편만 셌다).
  test "a report written through the wizard counts toward the challenge after it is submitted" do
    challenge = Challenge.create!(title: "단계 학습 챌린지", scope: :global)
    login_as @student
    post join_challenge_path(challenge)

    (1..5).each { |step| post advance_learn_index_path, params: { step: step, answer: "#{step}단계 답" } }
    draft = @student.reports.order(:id).last

    assert_nil draft.submitted_at, "위저드는 초안까지만 만든다"
    assert_empty RankingBoard.new(@student).challenge_ranking(challenge), "초안은 순위에 세지 않는다"

    patch report_path(draft), params: { report: { book_title: draft.book_title, body: draft.body } }
    assert_equal 1, RankingBoard.new(@student).challenge_ranking(challenge).first.score
  end

  # 단계 학습은 독후감을 쓰는 학생의 도구다(LearnPolicy — 앱 화면에 교직원 진입점도 없다). 진행이 DB 행이 된
  # 뒤로는 담임이 몇 단계 답하다 마지막에 막히면(ReportPolicy#create?) 고아 진행 행이 남았다(B·C 리뷰).
  test "the wizard is for students only" do
    teacher = User.create!(school: @school, name: "위저드담임", role: :teacher, password: "password")
    login_as teacher

    get learn_index_path
    assert_response :forbidden
    post advance_learn_index_path, params: { step: 1, answer: "1단계 답" }
    assert_response :forbidden
    assert_not LearnWizardProgress.exists?(user: teacher)
  end

  # 학급이 없는 학생은 독후감을 만들 수 없다(Report 는 학급 필수). 영어 검증 문구("Classroom must exist")를
  # 그대로 띄우지 않고 무엇을 해야 하는지 알려 주며, 쓴 답은 남긴다(B·C 리뷰).
  test "a student without a classroom is told why the draft cannot be made" do
    student = User.create!(school: @school, name: "학급없이마침", password: "password")
    login_as student
    (1..4).each { |step| post advance_learn_index_path, params: { step: step, answer: "#{step}단계 답" } }

    assert_no_difference -> { Report.count } do
      post advance_learn_index_path, params: { step: 5, answer: "5단계 답" }
    end
    assert_redirected_to learn_index_path
    assert_match "학급", flash[:alert]
    assert_no_match(/must exist/, flash[:alert])
    assert_equal "5단계 답", LearnWizardProgress.find_by(user: student).answers["5"]
  end

  # 마지막 단계가 두 번 오면(연타·다른 탭) 두 번째는 이미 끝난 것이다. 진행 행을 빈 채로 새로 만들면
  # "1단계 첫 줄이 비었어요"로 보여 다 쓴 아이가 답이 사라진 줄 안다(B·C 리뷰) — 쓰던 글 목록으로 보낸다.
  test "finishing the wizard twice does not look like the answers vanished" do
    login_as @student
    (1..5).each { |step| post advance_learn_index_path, params: { step: step, answer: "#{step}단계 답" } }
    assert_response :redirect

    assert_no_difference -> { Report.count } do
      post advance_learn_index_path, params: { step: 5, answer: "5단계 답" }
    end
    assert_redirected_to reports_path
    assert_match "이미 마쳤어요", flash[:notice]
    assert_not LearnWizardProgress.exists?(user: @student), "빈 진행 행을 새로 만들지 않는다"
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
