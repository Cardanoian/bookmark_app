require "test_helper"

# 마이페이지 비밀번호 변경(WS-G). 본인 확인(현재 비밀번호) 후 갱신, fail-closed 인가망 통과,
# 로그인 게이트를 검증한다. 헤더 로그아웃 이동은 통합(student_header_profile_test)에서 확인.
class PasswordsTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "비번변경초등학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 3)
    @student = User.create!(
      school: @school, classroom: @classroom, name: "비번학생", password: "password"
    )
  end

  test "edit renders the password change form for the signed-in user" do
    login_as @student

    get edit_password_path

    assert_response :success
    assert_select "form[action='#{password_path}']"
    assert_select "input[name='current_password']"
    assert_select "input[name='password']"
    assert_select "input[name='password_confirmation']"
  end

  test "the correct current password changes the password" do
    login_as @student

    patch password_path, params: {
      current_password: "password", password: "newsecret", password_confirmation: "newsecret"
    }

    assert_redirected_to profile_path
    assert @student.reload.authenticate("newsecret"), "새 비밀번호로 인증돼야 한다"
  end

  test "a wrong current password is rejected and leaves the password unchanged" do
    login_as @student

    patch password_path, params: {
      current_password: "wrong-password", password: "newsecret", password_confirmation: "newsecret"
    }

    assert_response :unprocessable_entity
    assert @student.reload.authenticate("password"), "기존 비밀번호가 유지돼야 한다"
    assert_not @student.authenticate("newsecret")
  end

  test "a too-short new password is rejected even with the correct current password" do
    login_as @student

    patch password_path, params: {
      current_password: "password", password: "123", password_confirmation: "123"
    }

    assert_response :unprocessable_entity
    assert @student.reload.authenticate("password"), "기존 비밀번호가 유지돼야 한다"
  end

  test "a mismatched confirmation is rejected" do
    login_as @student

    patch password_path, params: {
      current_password: "password", password: "newsecret", password_confirmation: "different"
    }

    assert_response :unprocessable_entity
    assert @student.reload.authenticate("password")
  end

  # fail-closed 인가 안전망(verify_authorized) 우회 확인 — skip 되지 않았다면 성공 경로가
  # AuthorizationNotPerformedError 로 500 이 된다. 정상 리다이렉트면 안전망을 통과한 것이다.
  test "the update passes the fail-closed authorization safety net" do
    login_as @student

    patch password_path, params: {
      current_password: "password", password: "newsecret", password_confirmation: "newsecret"
    }

    assert_response :redirect
  end

  test "the password screens require login" do
    get edit_password_path
    assert_redirected_to new_session_path

    patch password_path, params: { current_password: "password", password: "newsecret" }
    assert_redirected_to new_session_path
  end
end
