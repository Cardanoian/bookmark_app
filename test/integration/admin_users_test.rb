require "test_helper"

# P7.2 총괄관리자 사용자 관리: 검색·정지/해제·비밀번호 초기화·역할 부여 + 정지 로그인 차단.
class AdminUsersTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "관리학교")
    @classroom = Classroom.create!(school: @school, grade: 6, class_no: 2)
    @superadmin = User.create!(name: "총괄", role: :superadmin, password: "password")
    @student = User.create!(school: @school, classroom: @classroom, name: "김학생", role: :student, password: "password")
  end

  test "index searches by name" do
    User.create!(school: @school, classroom: @classroom, name: "다른아이", role: :student, password: "password")
    login_as @superadmin
    get admin_users_path(q: "김학생")
    assert_response :success
    assert_match "김학생", response.body
    assert_no_match "다른아이", response.body
  end

  test "index filters by role" do
    login_as @superadmin
    get admin_users_path(role: "superadmin")
    assert_response :success
    assert_match "총괄", response.body
    assert_no_match "김학생", response.body
  end

  test "show displays points and accumulated experience together" do
    @student.update!(points: 30, experience: 80)
    login_as @superadmin

    get admin_user_path(@student)

    assert_response :success
    assert_match "경험치", response.body
    assert_match "80", response.body
    assert_select "form[action=?]", reset_password_admin_user_path(@student) do
      assert_select "input[type=?][name=?][minlength=?][required]", "password", "user[password]", "6"
    end
  end

  test "suspend sets suspended true" do
    login_as @superadmin
    post suspend_admin_user_path(@student)
    assert @student.reload.suspended?
  end

  test "unsuspend clears suspended" do
    @student.update!(suspended: true)
    login_as @superadmin
    post unsuspend_admin_user_path(@student)
    assert_not @student.reload.suspended?
  end

  test "reset_password stores the admin supplied password as a hash" do
    login_as @superadmin
    password = "new123"
    post reset_password_admin_user_path(@student), params: { user: { password: password } }
    @student.reload

    assert @student.authenticate(password)
    assert_not @student.authenticate("password")
    assert_not_equal password, @student.password_digest, "password must be hashed, not plaintext"
    assert_not_includes flash[:notice], password
  end

  test "reset_password rejects blank whitespace-only and short passwords without changing the password" do
    login_as @superadmin

    [ "", "      ", "12345" ].each do |password|
      post reset_password_admin_user_path(@student), params: { user: { password: password } }

      assert @student.reload.authenticate("password")
      assert flash[:alert].present?
    end
  end

  test "role change updates the role" do
    login_as @superadmin
    patch role_admin_user_path(@student), params: { role: "teacher" }
    assert_equal "teacher", @student.reload.role
  end

  test "role change rejects an invalid role" do
    login_as @superadmin
    patch role_admin_user_path(@student), params: { role: "wizard" }
    assert_equal "student", @student.reload.role
  end

  test "a suspended user cannot log in" do
    @student.update!(suspended: true)
    login_as @student
    assert_response :forbidden
    assert_nil session[:user_id]
  end

  # #9: 관리자 포인트 조정은 raw :points 대입이 아니라 award_points 델타를 경유한다
  # (뱃지·진화·랭킹 후크 연쇄). 랭킹 방송이 발생하면 award_points 를 탄 것.
  test "admin points grant routes through award_points so the ranking hook fires" do
    login_as @superadmin
    assert_turbo_stream_broadcasts([ @classroom, :ranking ]) do
      patch admin_user_path(@student), params: { user: { name: @student.name, points: 500 } }
    end
    assert_equal 500, @student.reload.points
    assert_equal 500, @student.experience
  end

  # 목표값과의 차액(델타)만 반영한다(멱등 재적용 방지).
  test "admin points adjustment applies only the delta to the target value" do
    @student.update_columns(points: 100, experience: 400)
    login_as @superadmin
    patch admin_user_path(@student), params: { user: { name: @student.name, points: 250 } }
    assert_equal 250, @student.reload.points
    assert_equal 550, @student.experience, "상향 차액 150만큼 경험치도 적립"
  end

  # 하향 조정도 목표값에 안착한다(원자 차감, raw SQL 우회).
  test "admin can lower points to a target via atomic decrement" do
    @student.update_columns(points: 300, experience: 700)
    login_as @superadmin
    patch admin_user_path(@student), params: { user: { name: @student.name, points: 120 } }
    assert_equal 120, @student.reload.points
    assert_equal 700, @student.experience, "포인트 하향 조정은 누적 경험치를 낮추지 않는다"
  end

  # 음수 target 은 저장 없이 정확히 거부한다 — 예전엔 spend_points! 가 조용히 실패해도
  # "수정했어요"라고 거짓 안내했다(#9 후속: 보안 무해, UX 정합).
  test "a negative points target is rejected with no change instead of a false success" do
    @student.update_columns(points: 100)
    login_as @superadmin
    patch admin_user_path(@student), params: { user: { name: @student.name, points: -50 } }
    assert_response :unprocessable_entity
    assert_equal 100, @student.reload.points, "음수 target 은 반영되지 않는다"
    assert_match "0 이상의 정수", response.body, "거짓 성공 대신 정확한 안내가 화면에 보인다"
  end

  # 비정수 target(소수·문자)도 거부한다.
  test "a non-integer points target is rejected" do
    @student.update_columns(points: 100)
    login_as @superadmin
    patch admin_user_path(@student), params: { user: { name: @student.name, points: "12.5" } }
    assert_response :unprocessable_entity
    assert_equal 100, @student.reload.points
  end

  # 0 으로의 하향(정상 경계)은 그대로 반영된다(잔액 이내 차감 성공).
  test "lowering points to zero succeeds and lands on the target" do
    @student.update_columns(points: 80)
    login_as @superadmin
    patch admin_user_path(@student), params: { user: { name: @student.name, points: 0 } }
    assert_redirected_to admin_user_path(@student)
    assert_equal 0, @student.reload.points
  end

  test "a user suspended mid-session is logged out on the next request" do
    login_as @student
    get root_path
    assert_response :success

    @student.update!(suspended: true)
    get root_path
    assert_redirected_to new_session_path
  end

  private
end
