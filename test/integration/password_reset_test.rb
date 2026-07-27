require "test_helper"

# 교직원 이메일 비밀번호 재설정. 핵심 계약 셋:
#   ① 학생은 이 경로로 절대 재설정되지 않는다(fail-closed)
#   ② 계정 존재 여부가 응답으로 새지 않는다(열거 방지)
#   ③ 재설정 성공이 곧 토큰 소비다(1회용 성질)
class PasswordResetTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "재설정학교")
    @classroom = Classroom.create!(school: @school, grade: 4, class_no: 2)
    @teacher = User.create!(name: "김선생", email: "reset-teacher@example.com",
                            role: :teacher, school: @school, password: "password")
    PasswordResetsController.rate_limit_store = ActiveSupport::Cache::MemoryStore.new
  end

  teardown { PasswordResetsController.rate_limit_store = nil }

  test "staff request enqueues exactly one mail and shows the neutral notice" do
    assert_enqueued_emails 1 do
      post password_resets_path, params: { email: @teacher.email }
    end

    assert_response :success
    assert_match "메일을 확인해 주세요", response.body
  end

  test "email is normalized before lookup" do
    assert_enqueued_emails 1 do
      post password_resets_path, params: { email: "  RESET-Teacher@Example.COM  " }
    end
  end

  # --- 열거 방지: 아래 네 경우의 응답이 성공 요청과 완전히 같아야 한다 ---

  test "unknown address yields the same response and sends nothing" do
    assert_no_enqueued_emails do
      post password_resets_path, params: { email: "nobody@example.com" }
    end

    assert_response :success
    assert_match "메일을 확인해 주세요", response.body
  end

  test "student address yields the same response and sends nothing" do
    student = User.create!(name: "이학생", role: :student, school: @school,
                           classroom: @classroom, password: "password")
    student.update_column(:email, "reset-student@example.com")

    assert_no_enqueued_emails do
      post password_resets_path, params: { email: "reset-student@example.com" }
    end

    assert_response :success
    assert_match "메일을 확인해 주세요", response.body
  end

  test "suspended staff yields the same response and sends nothing" do
    @teacher.update!(suspended: true)

    assert_no_enqueued_emails do
      post password_resets_path, params: { email: @teacher.email }
    end

    assert_response :success
  end

  test "throttled request is indistinguishable from a successful one" do
    (MailRateLimiting::ACCOUNT_THROTTLE[:limit] + 1).times do
      post password_resets_path, params: { email: @teacher.email }
    end

    assert_response :success
    assert_match "메일을 확인해 주세요", response.body

    assert_no_enqueued_emails do
      post password_resets_path, params: { email: @teacher.email }
    end
  end

  # --- 토큰 소비 ---

  test "valid token renders the new password form" do
    get edit_password_reset_path(token: reset_token)

    assert_response :success
    assert_select "input[type=?][name=?]", "password", "password"
  end

  test "expired or forged token renders the re-request notice" do
    get edit_password_reset_path(token: "forged")

    assert_response :unprocessable_entity
    assert_match "링크를 쓸 수 없어요", response.body
  end

  test "successful reset changes the password and invalidates the token" do
    token = reset_token

    patch password_reset_path(token: token),
          params: { password: "brandnew", password_confirmation: "brandnew" }

    assert_redirected_to staff_login_path
    assert @teacher.reload.authenticate("brandnew")

    # 같은 토큰 재사용은 salt 변경으로 무효 — 1회용 성질의 실동작 검증.
    get edit_password_reset_path(token: token)
    assert_response :unprocessable_entity
  end

  test "reset clears any existing session" do
    login_as @teacher
    get root_path
    assert_response :success

    patch password_reset_path(token: reset_token),
          params: { password: "brandnew", password_confirmation: "brandnew" }

    get root_path
    assert_redirected_to new_session_path, "재설정 후에는 기존 세션이 무효가 되어야 한다"
  end

  test "blank or mismatched password is rejected without changing anything" do
    patch password_reset_path(token: reset_token), params: { password: "" }
    assert_response :unprocessable_entity

    patch password_reset_path(token: reset_token),
          params: { password: "abcdef", password_confirmation: "zzzzzz" }
    assert_response :unprocessable_entity

    assert @teacher.reload.authenticate("password"), "실패한 재설정이 비밀번호를 바꿔서는 안 된다"
  end

  test "token issued before suspension stops working" do
    token = reset_token
    @teacher.update!(suspended: true)

    get edit_password_reset_path(token: token)

    assert_response :unprocessable_entity, "발급 시점 판정만 믿지 않고 사용 시점에 자격을 재확인해야 한다"
  end

  # --- 감사 로그 ---

  test "request and completion are audited without leaking the token" do
    post password_resets_path, params: { email: @teacher.email }
    requested = AuditLog.find_by(action: "auth.password_reset_requested")
    assert_equal @teacher.id, requested.target_id

    token = reset_token
    patch password_reset_path(token: token),
          params: { password: "brandnew", password_confirmation: "brandnew" }

    completed = AuditLog.find_by(action: "auth.password_reset_completed")
    assert_equal @teacher.id, completed.target_id
    AuditLog.where(action: [ "auth.password_reset_requested", "auth.password_reset_completed" ]).each do |log|
      assert_not_includes log.metadata.to_s, token
    end
  end

  private

  def reset_token
    @teacher.generate_token_for(:password_reset)
  end
end
