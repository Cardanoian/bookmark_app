require "test_helper"

class SessionsTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "로그인초등학교")
    @classroom = Classroom.create!(school: @school, grade: 3, class_no: 1)
    @user = User.create!(
      school: @school, classroom: @classroom, name: "로그인학생", password: "password"
    )
    @teacher = User.create!(
      school: @school, classroom: @classroom, name: "로그인교사",
      role: :teacher, email: "teacher@login.test", password: "password"
    )
  end

  # ── 안내 인덱스(선택 화면) ─────────────────────────────────────────────
  test "the landing index offers login choices and a teacher registration card" do
    get new_session_path

    assert_response :success
    assert_includes response.body, "학생 로그인"
    assert_includes response.body, "선생님 로그인"
    assert_includes response.body, student_login_path
    assert_includes response.body, staff_login_path
    assert_select "a.card[href='#{new_registration_path}']" do
      assert_select "svg use[href$='#document']", count: 1
      assert_select "span", text: "선생님 회원가입"
      assert_select "span", text: "가입 후 바로 활동할 수 있어요"
    end
  end

  test "an unauthenticated request redirects to the landing index without an alert" do
    get root_path

    assert_redirected_to new_session_path
    assert_nil flash[:alert]

    follow_redirect!
    assert_response :success
    assert_not_includes response.body, "로그인이 필요합니다."
  end

  # ── 학생 로그인(튜플) ─────────────────────────────────────────────────
  test "student login form renders the hybrid school picker with scoped classroom dropdown" do
    School.create!(name: "로그인목록에없어야할초", region: "제주특별자치도교육청", gu: "제주시")

    get student_login_path

    assert_response :success
    assert_includes response.body, 'data-controller="school-picker"'
    assert_includes response.body, 'data-school-picker-target="classroom"', "학생 로그인 폼은 스코프 학급 드롭다운을 포함"
    assert_includes response.body, "제주특별자치도", "시도(교육청) 옵션은 서버 렌더"
    assert_not_includes response.body, "로그인목록에없어야할초", "학교는 전량 서버 렌더하지 않는다(AJAX 로드)"
  end

  test "successful student login redirects to root and sets the session" do
    post student_login_path, params: {
      school_id: @school.id, classroom_id: @classroom.id,
      name: "로그인학생", password: "password"
    }

    assert_redirected_to root_path
    assert_equal @user.id, session[:user_id]
  end

  test "bad student credentials re-render the student form with 422" do
    post student_login_path, params: {
      school_id: @school.id, classroom_id: @classroom.id,
      name: "로그인학생", password: "wrong-password"
    }

    assert_response :unprocessable_entity
    assert_nil session[:user_id]
  end

  # ── 교직원 로그인(이메일) ─────────────────────────────────────────────
  test "staff login form renders an email field" do
    get staff_login_path

    assert_response :success
    assert_includes response.body, 'type="email"'
    assert_includes response.body, "선생님 로그인"
    assert_select "a.btn.btn-secondary.btn-block[href='#{new_registration_path}']", text: "선생님 회원가입"
  end

  test "successful staff login by email redirects to root and sets the session" do
    post staff_login_path, params: { email: "teacher@login.test", password: "password" }

    assert_redirected_to root_path
    assert_equal @teacher.id, session[:user_id]
  end

  test "staff login is case-insensitive on email" do
    post staff_login_path, params: { email: "  TEACHER@Login.Test  ", password: "password" }

    assert_redirected_to root_path
    assert_equal @teacher.id, session[:user_id]
  end

  test "bad staff credentials re-render the staff form with 422" do
    post staff_login_path, params: { email: "teacher@login.test", password: "wrong-password" }

    assert_response :unprocessable_entity
    assert_nil session[:user_id]
  end

  test "unknown staff email re-renders the staff form with 422" do
    post staff_login_path, params: { email: "nobody@login.test", password: "password" }

    assert_response :unprocessable_entity
    assert_nil session[:user_id]
  end

  # ── 표면 격리(신원 방식 교차 차단) ────────────────────────────────────
  test "a staff member cannot log in through the student (tuple) form" do
    post student_login_path, params: {
      school_id: @teacher.school_id, classroom_id: @teacher.classroom_id,
      name: @teacher.name, password: "password"
    }

    assert_response :unprocessable_entity, "교직원은 학생 폼(튜플)으로 로그인할 수 없다"
    assert_nil session[:user_id]
  end

  test "a student cannot log in through the staff (email) form" do
    @user.update_column(:email, "student@login.test") # 학생에게 이메일이 있어도 교직원 폼은 학생을 조회하지 않는다

    post staff_login_path, params: { email: "student@login.test", password: "password" }

    assert_response :unprocessable_entity, "학생은 교직원 폼(이메일)으로 로그인할 수 없다"
    assert_nil session[:user_id]
  end

  # ── 체험 계정 원클릭 로그인 ───────────────────────────────────────────
  # role 만 받고 계정은 서버(DemoAccounts)가 확정한다 — 페이지 소스에 자격증명이 남지 않는다.
  test "the landing index hides the demo section when the sample accounts are absent" do
    get new_session_path

    assert_response :success
    assert_not_includes response.body, "바로 체험해 보기"
    assert_select "form[action=?]", demo_login_path, count: 0
  end

  test "the landing index offers demo buttons when the sample accounts exist" do
    create_demo_accounts!

    get new_session_path

    assert_response :success
    assert_includes response.body, "바로 체험해 보기"
    assert_select "form[action=?]", demo_login_path, count: 2
    assert_select "button", text: /학생으로 체험하기/
    assert_select "button", text: /선생님으로 체험하기/
    # 비밀번호는 서버가 확정하므로 마크업에 새지 않는다.
    assert_not_includes response.body, "student1234"
    assert_not_includes response.body, "jieun11!"
  end

  test "the student demo button logs in as the sample student without a password" do
    student, = create_demo_accounts!

    post demo_login_path, params: { role: "student" }

    assert_redirected_to root_path
    assert_equal student.id, session[:user_id]
  end

  test "the teacher demo button logs in as the sample homeroom teacher" do
    _student, teacher = create_demo_accounts!

    post demo_login_path, params: { role: "teacher" }

    assert_redirected_to root_path
    assert_equal teacher.id, session[:user_id]
  end

  test "an unknown demo role grants no session" do
    create_demo_accounts!

    post demo_login_path, params: { role: "superadmin" }

    assert_redirected_to new_session_path
    assert_equal "체험 계정을 찾을 수 없어요.", flash[:alert]
    assert_nil session[:user_id]
  end

  test "a missing demo role grants no session" do
    create_demo_accounts!

    post demo_login_path

    assert_redirected_to new_session_path
    assert_nil session[:user_id]
  end

  test "demo login grants no session when the sample accounts do not exist" do
    post demo_login_path, params: { role: "student" }

    assert_redirected_to new_session_path
    assert_equal "체험 계정을 찾을 수 없어요.", flash[:alert]
    assert_nil session[:user_id]
  end

  # 정지 계정 게이트는 일반 로그인과 공유한다(handle_authenticated).
  test "a suspended demo account cannot log in" do
    student, = create_demo_accounts!
    student.update!(suspended: true)

    post demo_login_path, params: { role: "student" }

    assert_response :forbidden
    assert_nil session[:user_id]
  end

  # ── 로그아웃 ─────────────────────────────────────────────────────────
  test "logout resets the session" do
    post student_login_path, params: {
      school_id: @school.id, classroom_id: @classroom.id,
      name: "로그인학생", password: "password"
    }
    assert_equal @user.id, session[:user_id]

    delete session_path
    assert_redirected_to new_session_path
    assert_nil session[:user_id]
  end

  # #7(fail2ban): **오답만** 카운트하고 한도 초과 시 추가 **추측(오답)**을 락아웃한다.
  # 테스트 캐시는 :null_store 라 무카운팅이므로 카운팅 가능한 인메모리 스토어를 주입한다.
  # 스로틀 로직은 학생·교직원 표면이 공유하므로 학생 폼으로 대표 검증한다.
  test "wrong-password guesses lock out further guesses after the account limit" do
    SessionsController.rate_limit_store = ActiveSupport::Cache::MemoryStore.new

    SessionsController::ACCOUNT_THROTTLE[:limit].times do
      post student_login_path, params: account_params(password: "wrong-password")
      assert_response :unprocessable_entity, "한도 이내 오답은 스로틀되지 않는다"
    end

    # 한도 초과 → 추가 오답(추측)은 락아웃(429).
    post student_login_path, params: account_params(password: "wrong-password")
    assert_response :too_many_requests, "한도 초과 후 오답은 락아웃"
  end

  # DoS 방지: 오답이 한도를 넘어도 **정답은 항상** 로그인되고 실패 카운터를 리셋한다 →
  # 저엔트로피 파라미터로 피해자 계정을 잠그는 DoS 가 성립하지 않는다.
  test "a correct password always logs in even after failed guesses (no victim lockout DoS)" do
    SessionsController.rate_limit_store = ActiveSupport::Cache::MemoryStore.new

    SessionsController::ACCOUNT_THROTTLE[:limit].times do
      post student_login_path, params: account_params(password: "wrong-password")
    end

    post student_login_path, params: account_params(password: "password")
    assert_redirected_to root_path, "정답은 락아웃되지 않고 로그인된다(피해자 DoS 방지)"
    assert_equal @user.id, session[:user_id]
  end

  # NAT 방지: 전산실 단일 IP 뒤 여러 학생이 정답으로 연속 로그인해도(실패 0) IP 한도에 안 걸린다.
  test "simultaneous correct logins from one IP are never throttled (only failures count)" do
    SessionsController.rate_limit_store = ActiveSupport::Cache::MemoryStore.new

    (SessionsController::IP_THROTTLE[:limit] + 3).times do |i|
      student = User.create!(school: @school, classroom: @classroom, name: "동시학생#{i}", password: "password")
      post student_login_path, params: {
        school_id: student.school_id, classroom_id: student.classroom_id,
        name: student.name, password: "password"
      }
      assert_redirected_to root_path, "정답 동시 로그인은 IP 한도에 걸리지 않는다"
      delete session_path
    end
  end

  # 계정키 정규화: id 문자열 변형("5"/"05"/" 5 ")으로 실패를 나눠 쌓아도 같은 user.id 버킷에
  # 합산되어 우회할 수 없다(과거엔 원문 문자열 키라 버킷이 분열돼 스로틀을 우회).
  test "account-key id string variants collapse to one bucket (bypass closed)" do
    SessionsController.rate_limit_store = ActiveSupport::Cache::MemoryStore.new
    variants = [ @school.id.to_s, "0#{@school.id}", " #{@school.id} " ]

    SessionsController::ACCOUNT_THROTTLE[:limit].times do |i|
      post student_login_path, params: {
        school_id: variants[i % variants.size], classroom_id: @classroom.id,
        name: "로그인학생", password: "wrong-password"
      }
    end

    post student_login_path, params: account_params(password: "wrong-password")
    assert_response :too_many_requests, "id 문자열 변형으로 계정 스로틀을 우회할 수 없다"
  end

  # 락아웃은 계정별로 격리 — 한 계정이 잠겨도 다른 계정은 정상 로그인.
  test "account lockout is isolated per account" do
    SessionsController.rate_limit_store = ActiveSupport::Cache::MemoryStore.new
    other = User.create!(school: @school, classroom: @classroom, name: "다른로그인학생", password: "password")

    SessionsController::ACCOUNT_THROTTLE[:limit].times do
      post student_login_path, params: account_params(password: "wrong-password")
    end
    post student_login_path, params: account_params(password: "wrong-password")
    assert_response :too_many_requests, "대상 계정의 추가 오답은 잠긴다"

    post student_login_path, params: {
      school_id: other.school_id, classroom_id: other.classroom_id,
      name: other.name, password: "password"
    }
    assert_redirected_to root_path, "다른 계정은 정상 로그인"
    assert_equal other.id, session[:user_id]
  end

  # 저장소 주입이 카운팅 상태를 담는다 — null_store(기본 test 캐시)면 무카운팅 → 무스로틀.
  test "no counting store means no throttle (state lives in the injected store, not a singleton)" do
    SessionsController.rate_limit_store = nil # → Rails.cache(:null_store)

    (SessionsController::ACCOUNT_THROTTLE[:limit] + 5).times do
      post student_login_path, params: account_params(password: "wrong-password")
      assert_response :unprocessable_entity, "무카운팅 스토어에서는 스로틀되지 않는다"
    end
  end

  teardown do
    SessionsController.rate_limit_store = nil
  end

  private

  def account_params(password:)
    { school_id: @school.id, classroom_id: @classroom.id, name: "로그인학생", password: password }
  end

  # db/seeds/accounts.yml 의 sample_accounts 와 같은 신원(포항원동초 3-1 이도현 / 담임 김지은)을
  # 만든다. DemoAccounts 상수를 그대로 써서 시드 값이 바뀌면 테스트가 함께 따라간다.
  def create_demo_accounts!
    school = School.create!(name: "포항원동초등학교", neis_code: DemoAccounts::SCHOOL_NEIS_CODE)
    classroom = Classroom.create!(
      school: school, grade: DemoAccounts::GRADE, class_no: DemoAccounts::CLASS_NO
    )
    student = User.create!(
      school: school, classroom: classroom, name: DemoAccounts::STUDENT_NAME,
      nickname: "체험독서왕", password: "student1234"
    )
    teacher = User.create!(
      school: school, name: "김지은", role: :teacher,
      email: DemoAccounts::TEACHER_EMAIL, password: "jieun11!"
    )
    [ student, teacher ]
  end
end
