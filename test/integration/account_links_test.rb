require "test_helper"

# 계정 연동(MERGE) 학생 셀프서브 e2e(account_linking_seasons_plan §Phase 3).
# 플래그 게이트·preview→confirm 세션 스왑·스로틀(계정 축 공유 / IP 축 분리 / store 시임)·
# 자기연동/현재계정 거부·이미연동 숨김·confirm redirect(turbo 미사용).
class AccountLinksTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "연동초등학교")
    @current = Classroom.current_academic_year
    @old_classroom = Classroom.create!(school: @school, grade: 3, class_no: 1, academic_year: @current - 1)
    @new_classroom = Classroom.create!(school: @school, grade: 4, class_no: 1, academic_year: @current)

    @old = User.create!(school: @school, classroom: @old_classroom, name: "홍길동", password: "oldpass1")
    @new = User.create!(school: @school, classroom: @new_classroom, name: "홍길동", password: "newpass1")

    Report.create!(user: @old, classroom: @old_classroom, book_title: "작년책", reviewed: true)
    Report.create!(user: @new, classroom: @new_classroom, book_title: "올해책", reviewed: true)

    enable_account_linking!
  end

  teardown do
    AccountLinksController.rate_limit_store = nil
    SessionsController.rate_limit_store = nil
  end

  # ── 플래그 게이트 ────────────────────────────────────────────────────
  test "플래그 off 면 진입점 미노출 + 직접 URL 리다이렉트" do
    AppSetting.set("feature_flags", { "account_linking" => false })
    login_as(@new, password: "newpass1")

    get profile_path
    assert_response :success
    assert_not_includes response.body, "계정 연동하기"

    get new_account_link_path
    assert_redirected_to root_path

    post preview_account_link_path, params: old_params(password: "oldpass1")
    assert_redirected_to root_path
  end

  test "플래그 on 이면 마이페이지에 진입점이 뜬다" do
    login_as(@new, password: "newpass1")

    get profile_path
    assert_response :success
    assert_includes response.body, "계정 연동하기"
    assert_includes response.body, new_account_link_path
  end

  # ── preview → confirm 세션 스왑 ──────────────────────────────────────
  test "유효한 작년 자격증명으로 미리보기하면 생존자 자산을 보여 준다" do
    login_as(@new, password: "newpass1")

    post preview_account_link_path, params: old_params(password: "oldpass1")

    assert_response :success
    assert_includes response.body, @old.name
    assert_includes response.body, "독후감"
    assert_not_nil token_from_response, "확인화면에 서명 토큰이 있어야 한다"
  end

  test "확정하면 세션이 생존자로 스왑되고 현재 학급·이름·비번을 유지한 채 기록이 합쳐진다" do
    login_as(@new, password: "newpass1")
    token = preview_and_token

    post confirm_account_link_path, params: { token: token }

    assert_redirected_to profile_path
    assert_equal @old.id, session[:user_id], "세션이 생존자(작년 계정)로 스왑"
    assert_not User.exists?(@new.id), "placeholder 삭제"

    @old.reload
    assert_equal @new_classroom.id, @old.classroom_id, "현재 학급 승계"
    assert_equal "홍길동", @old.name
    assert @old.authenticate("newpass1"), "현재(placeholder) 비밀번호 승계"
    assert_equal 2, @old.reports.count, "작년+올해 독후감 합쳐짐"
  end

  test "확정 응답은 turbo_stream 이 아니라 리다이렉트다" do
    login_as(@new, password: "newpass1")
    token = preview_and_token

    post confirm_account_link_path, params: { token: token }

    assert_response :redirect
    assert_not_equal "text/vnd.turbo-stream.html", response.media_type
  end

  test "만료·위조 토큰은 확정되지 않고 재안내한다" do
    login_as(@new, password: "newpass1")

    post confirm_account_link_path, params: { token: "garbage" }

    assert_redirected_to new_account_link_path
    assert User.exists?(@new.id), "위조 토큰으로는 병합되지 않는다"
  end

  # ── 자기연동 / 이미연동 ──────────────────────────────────────────────
  test "자기 현재 계정으로는 연동할 수 없다" do
    login_as(@new, password: "newpass1")

    post preview_account_link_path, params: {
      school_id: @school.id, classroom_id: @new_classroom.id,
      academic_year: @new_classroom.academic_year, name: "홍길동", password: "newpass1"
    }

    assert_response :unprocessable_entity
  end

  test "이미 연동한(생존자) 계정 마이페이지는 진입점을 숨긴다" do
    login_as(@new, password: "newpass1")
    token = preview_and_token
    post confirm_account_link_path, params: { token: token } # 세션은 이제 생존자(@old)

    get profile_path
    assert_response :success
    assert_not_includes response.body, "계정 연동하기", "이미 연동했으면 숨김"
  end

  # ── 스로틀(계정 축 공유 / IP 축 분리 / store 시임) ────────────────────
  test "오답 반복은 계정 한도 초과 후 락아웃된다(store 시임 주입)" do
    AccountLinksController.rate_limit_store = ActiveSupport::Cache::MemoryStore.new
    login_as(@new, password: "newpass1")

    LoginThrottling::ACCOUNT_THROTTLE[:limit].times do
      post preview_account_link_path, params: old_params(password: "wrong")
      assert_response :unprocessable_entity, "한도 이내 오답은 스로틀되지 않는다"
    end

    post preview_account_link_path, params: old_params(password: "wrong")
    assert_response :too_many_requests, "한도 초과 후 오답은 락아웃"
  end

  test "계정 축 공유 — 연동 실패가 같은 작년 계정의 로그인 락아웃에 합산된다" do
    store = ActiveSupport::Cache::MemoryStore.new
    AccountLinksController.rate_limit_store = store
    SessionsController.rate_limit_store = store # 같은 스토어라야 축 공유가 관측된다(프로덕션=공용 Solid Cache)

    login_as(@new, password: "newpass1")
    LoginThrottling::ACCOUNT_THROTTLE[:limit].times do
      post preview_account_link_path, params: old_params(password: "wrong")
    end
    delete session_path

    # 작년 계정(@old)을 학생 로그인 폼으로 오답 시도 → 연동에서 쌓인 계정 축 실패로 이미 락아웃.
    post student_login_path, params: {
      school_id: @school.id, classroom_id: @old_classroom.id, name: "홍길동", password: "wrong"
    }
    assert_response :too_many_requests, "login:account: 네임스페이스를 공유해 표면 간 합산"
  end

  test "IP 축 분리 — 연동 IP 실패가 로그인 IP 가용성을 오염시키지 않는다" do
    store = ActiveSupport::Cache::MemoryStore.new
    AccountLinksController.rate_limit_store = store
    SessionsController.rate_limit_store = store

    login_as(@new, password: "newpass1")
    # 서로 다른(미존재) 작년 이름으로 IP 한도까지 실패 → linkauth:ip 축만 누적(계정 버킷은 분산).
    (LoginThrottling::IP_THROTTLE[:limit] + 1).times do |i|
      post preview_account_link_path, params: {
        school_id: @school.id, classroom_id: @old_classroom.id, name: "없는이름#{i}", password: "wrong"
      }
    end
    post preview_account_link_path, params: {
      school_id: @school.id, classroom_id: @old_classroom.id, name: "없는이름X", password: "wrong"
    }
    assert_response :too_many_requests, "linkauth:ip 축은 자체 락아웃된다"

    delete session_path
    # 같은 IP 의 학생 로그인(login:ip 축)은 오염되지 않아 정상 로그인.
    post student_login_path, params: {
      school_id: @school.id, classroom_id: @new_classroom.id, name: "홍길동", password: "newpass1"
    }
    assert_redirected_to root_path, "login:ip 축은 연동 IP 실패와 분리돼 가용"
  end

  private

  def enable_account_linking!
    AppSetting.set("feature_flags", { "account_linking" => true })
  end

  def old_params(password:)
    {
      school_id: @school.id, classroom_id: @old_classroom.id,
      academic_year: @old_classroom.academic_year, name: "홍길동", password: password
    }
  end

  def preview_and_token
    post preview_account_link_path, params: old_params(password: "oldpass1")
    assert_response :success
    token_from_response
  end

  def token_from_response
    node = css_select("input[name='token']").first
    node && node["value"]
  end
end
