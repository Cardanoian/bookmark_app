require "test_helper"

# 교사 가입 이메일 인증. 핵심 계약 셋:
#   ① 인증 도입이 "가입 즉시 로그인" 흐름을 바꾸지 않는다(회귀 방지)
#   ② 게이트는 fail-open — 무키 환경·유예 내에는 잠기지 않고, 잠겨도 읽기는 열려 있다
#   ③ 게이트가 잠그는 것은 남의 계정을 만들고 조작하는 두 액션뿐이다
class EmailVerificationTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "인증학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 3)
    @teacher = User.create!(name: "김선생", email: "verify-teacher@example.com",
                            role: :teacher, school: @school, classroom: @classroom,
                            password: "password")
    @classroom.update!(teacher: @teacher)
    EmailVerificationsController.rate_limit_store = ActiveSupport::Cache::MemoryStore.new
  end

  teardown { EmailVerificationsController.rate_limit_store = nil }

  # --- 가입 연동 ---

  test "signup sends the verification mail and still logs the teacher in immediately" do
    assert_enqueued_emails 1 do
      post registrations_path, params: {
        school_id: @school.id, name: "박신규",
        email: "brand-new@example.com", password: "password",
        grade: 6, class_no: 9
      }
    end

    assert_redirected_to root_path
    created = User.find_by(email: "brand-new@example.com")
    assert_not_nil created
    assert_nil created.email_verified_at, "가입 직후에는 미인증 상태여야 한다"

    follow_redirect!
    assert_response :success, "인증 도입이 가입 즉시 로그인 흐름을 막아서는 안 된다"
  end

  # --- 인증 링크 ---

  test "visiting a valid link marks the address verified" do
    get email_verification_path(token: verification_token)

    assert_redirected_to root_path
    assert @teacher.reload.email_verified?
    assert AuditLog.exists?(action: "auth.email_verified", target_id: @teacher.id)
  end

  test "visiting the link twice is idempotent and keeps the first timestamp" do
    token = verification_token
    get email_verification_path(token: token)
    first = @teacher.reload.email_verified_at

    travel 1.hour do
      get email_verification_path(token: token)
    end

    assert_redirected_to root_path
    assert_equal first, @teacher.reload.email_verified_at
  end

  test "forged link does not verify anything" do
    get email_verification_path(token: "forged")

    assert_redirected_to root_path
    assert_not @teacher.reload.email_verified?
  end

  # --- 재발송 ---

  test "resend delivers again and is audited" do
    login_as @teacher

    assert_enqueued_emails 1 do
      post resend_email_verification_path
    end

    assert AuditLog.exists?(action: "auth.email_verification_sent", target_id: @teacher.id)
  end

  test "resend is throttled per account" do
    login_as @teacher
    MailRateLimiting::ACCOUNT_THROTTLE[:limit].times { post resend_email_verification_path }

    assert_no_enqueued_emails { post resend_email_verification_path }
  end

  test "resend on an already verified account sends nothing" do
    @teacher.update!(email_verified_at: Time.current)
    login_as @teacher

    assert_no_enqueued_emails { post resend_email_verification_path }
  end

  test "resend requires login" do
    post resend_email_verification_path

    assert_redirected_to new_session_path
  end

  # --- 게이트 ---

  test "gate blocks student creation for an unverified teacher past the grace period" do
    expire_grace!
    login_as @teacher

    with_mail_delivery_available do
      assert_no_difference "User.count" do
        post teacher_students_path, params: student_payload("새학생")
      end
    end

    # 게이트 때문에 막혔음을 명시적으로 확인한다. 이 단언이 없으면 파라미터 오류로 생성이
    # 실패해도 테스트가 통과해 버린다(거짓 음성).
    assert_match "이메일 주소를 먼저 확인해 주세요", flash[:alert]
  end

  test "gate blocks student password reset for an unverified teacher past the grace period" do
    student = create_student
    expire_grace!
    login_as @teacher

    with_mail_delivery_available do
      post reset_password_teacher_student_path(student), params: { student: { password: "changed1" } }
    end

    assert_match "이메일 주소를 먼저 확인해 주세요", flash[:alert]
    assert student.reload.authenticate("password"), "게이트가 걸리면 비밀번호가 바뀌어서는 안 된다"
  end

  test "gate allows student creation during the grace period" do
    login_as @teacher

    with_mail_delivery_available do
      assert_difference "User.count", 1 do
        post teacher_students_path, params: student_payload("유예학생")
      end
    end
  end

  test "gate stays open when mail delivery is unavailable" do
    expire_grace!
    login_as @teacher

    assert_difference "User.count", 1 do
      post teacher_students_path, params: student_payload("무키학생")
    end
  end

  test "gate stays open for a verified teacher" do
    expire_grace!
    @teacher.update!(email_verified_at: Time.current)
    login_as @teacher

    with_mail_delivery_available do
      assert_difference "User.count", 1 do
        post teacher_students_path, params: student_payload("인증학생")
      end
    end
  end

  test "gate never blocks reading paths" do
    expire_grace!
    login_as @teacher

    with_mail_delivery_available do
      get teacher_students_path
      assert_response :success, "게이트가 걸려도 목록 열람은 계속 가능해야 한다"

      get teacher_dashboard_path
      assert_response :success
    end
  end

  # --- 배너 ---

  test "banner appears only when delivery is possible and the address is unverified" do
    login_as @teacher

    with_mail_delivery_available do
      get root_path
      assert_match "인증 메일 다시 보내기", response.body
    end

    get root_path
    assert_no_match "인증 메일 다시 보내기", response.body,
                    "발송 불가 환경에서는 죽은 버튼을 띄우지 않는다"
  end

  test "banner disappears once verified" do
    @teacher.update!(email_verified_at: Time.current)
    login_as @teacher

    with_mail_delivery_available do
      get root_path
      assert_no_match "인증 메일 다시 보내기", response.body
    end
  end

  private

  def verification_token
    @teacher.generate_token_for(:email_verification)
  end

  def expire_grace!
    @teacher.update_column(:created_at, (User::EMAIL_VERIFICATION_GRACE + 1.hour).ago)
  end

  def create_student
    User.create!(name: "기존학생", role: :student, school: @school,
                 classroom: @classroom, password: "password")
  end

  # Teacher::StudentsController#create 가 기대하는 형태 — classroom_id·privacy_consent 모두
  # `student` 아래 중첩이다(동의 필드는 permit 밖에서 서버가 직접 소비한다).
  def student_payload(name)
    { student: { name: name, password: "password",
                 classroom_id: @classroom.id, privacy_consent: "1" } }
  end
end
