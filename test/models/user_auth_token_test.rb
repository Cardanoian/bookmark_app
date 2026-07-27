require "test_helper"

# 비밀번호 재설정·이메일 인증 토큰(generates_token_for)과 자격 술어.
# 토큰은 DB 무저장이며 salt·email 바인딩으로 무효화된다 — 그 무효화가 실제로 일어나는지가 핵심.
class UserAuthTokenTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "토큰학교")
    @teacher = User.create!(name: "김선생", email: "token-teacher@example.com",
                            role: :teacher, school: @school, password: "password")
  end

  # --- 비밀번호 재설정 토큰 ---

  test "password_reset token round-trips to the same user" do
    token = @teacher.generate_token_for(:password_reset)

    assert_equal @teacher, User.find_by_token_for(:password_reset, token)
  end

  test "password_reset token is invalidated once the password changes" do
    token = @teacher.generate_token_for(:password_reset)
    @teacher.update!(password: "newpassword")

    assert_nil User.find_by_token_for(:password_reset, token),
               "비밀번호가 바뀌면 salt 가 바뀌어 이전 토큰이 모두 무효가 되어야 한다(1회용 성질의 근거)"
  end

  test "password_reset token expires" do
    token = @teacher.generate_token_for(:password_reset)

    travel (User::PASSWORD_RESET_EXPIRY + 1.minute) do
      assert_nil User.find_by_token_for(:password_reset, token)
    end
  end

  test "tampered password_reset token returns nil instead of raising" do
    assert_nil User.find_by_token_for(:password_reset, "not-a-real-token")
  end

  # --- 이메일 인증 토큰 ---

  test "email_verification token is invalidated when the email changes" do
    token = @teacher.generate_token_for(:email_verification)
    @teacher.update!(email: "token-teacher-changed@example.com")

    assert_nil User.find_by_token_for(:email_verification, token),
               "주소를 고치면 옛 주소로 간 링크가 새 주소를 인증해서는 안 된다"
  end

  test "email_verification token expires" do
    token = @teacher.generate_token_for(:email_verification)

    travel (User::EMAIL_VERIFICATION_EXPIRY + 1.minute) do
      assert_nil User.find_by_token_for(:email_verification, token)
    end
  end

  # --- 자격 술어 ---

  test "password_reset_eligible? excludes students even when they have an email" do
    classroom = Classroom.create!(school: @school, grade: 3, class_no: 1)
    student = User.create!(name: "이학생", role: :student, school: @school,
                           classroom: classroom, password: "password")
    student.update_column(:email, "student-with-email@example.com")

    assert_not student.reload.password_reset_eligible?,
               "학생은 이메일이 있어도 이메일 재설정 경로의 대상이 아니다(fail-closed)"
  end

  test "password_reset_eligible? excludes staff without an email or suspended" do
    no_email = User.create!(name: "무이메일", role: :librarian, school: @school, password: "password")
    assert_not no_email.password_reset_eligible?

    @teacher.update!(suspended: true)
    assert_not @teacher.password_reset_eligible?
  end

  test "password_reset_eligible? includes every staff role" do
    %i[teacher school_admin librarian superadmin].each_with_index do |role, index|
      staff = User.create!(name: "직원#{index}", email: "staff#{index}@example.com",
                           role: role, school: @school, password: "password")
      assert staff.password_reset_eligible?, "#{role} 은 이메일 재설정 대상이어야 한다"
    end
  end

  # --- 인증 게이트 ---

  test "gate stays open while mail delivery is unavailable" do
    @teacher.update_column(:created_at, 3.days.ago)

    assert_not @teacher.reload.email_verification_gate_active?,
               "키가 없는 환경(개발·CI·오프라인 시연)에서는 게이트가 통째로 꺼져야 한다"
  end

  test "gate stays open during the grace period even when mail works" do
    with_mail_delivery_available do
      assert_not @teacher.email_verification_gate_active?
    end
  end

  test "gate closes after the grace period for an unverified teacher" do
    @teacher.update_column(:created_at, (User::EMAIL_VERIFICATION_GRACE + 1.hour).ago)

    with_mail_delivery_available do
      assert @teacher.reload.email_verification_gate_active?
    end
  end

  test "gate stays open for a verified teacher" do
    @teacher.update_columns(created_at: 3.days.ago, email_verified_at: Time.current)

    with_mail_delivery_available do
      assert_not @teacher.reload.email_verification_gate_active?
    end
  end

  test "gate never applies to non-teacher roles" do
    librarian = User.create!(name: "사서", email: "gate-librarian@example.com",
                             role: :librarian, school: @school, password: "password")
    librarian.update_column(:created_at, 3.days.ago)

    with_mail_delivery_available do
      assert_not librarian.reload.email_verification_gate_active?
    end
  end
end
