require "test_helper"

# 계정 연동 교사 보조(account_linking_seasons_plan §Phase 4) — owned_student! 경계·서비스 공유·
# 세션 스왑 없음·14일 창·크로스학급 되돌리기 403·역할 게이트.
class TeacherAccountLinksTest < ActionDispatch::IntegrationTest
  setup do
    seed_monster_species!
    @school = School.create!(name: "교사연동초")
    current = Classroom.current_academic_year
    @classroom_a = Classroom.create!(school: @school, grade: 4, class_no: 1, academic_year: current)
    @classroom_b = Classroom.create!(school: @school, grade: 4, class_no: 2, academic_year: current)
    @old_classroom = Classroom.create!(school: @school, grade: 3, class_no: 1, academic_year: current - 1)
    @teacher_a = User.create!(school: @school, classroom: @classroom_a, name: "김담임",
                              role: :teacher, email: "ta@example.com", password: "password")
    @classroom_a.update!(teacher: @teacher_a)
    @teacher_b = User.create!(school: @school, classroom: @classroom_b, name: "이담임",
                              role: :teacher, email: "tb@example.com", password: "password")
    @classroom_b.update!(teacher: @teacher_b)
    @student_new = User.create!(school: @school, classroom: @classroom_a, name: "김이어", password: "npw123")
    @student_old = User.create!(school: @school, classroom: @old_classroom, name: "김이어", password: "opw123")
    Report.create!(user: @student_old, classroom: @old_classroom, book_title: "작년책", reviewed: true)
  end

  test "담임은 자기 학급 학생의 작년 계정을 연동한다(세션 스왑 없음)" do
    login_as(@teacher_a)

    assert_difference -> { User.count }, -1 do
      post teacher_account_links_path, params: { new_account_id: @student_new.id, old_account_id: @student_old.id }
    end

    assert_redirected_to teacher_account_links_path
    assert_equal @teacher_a.id, session[:user_id], "교사 세션 유지(스왑 없음)"
    assert_not User.exists?(@student_new.id)
    @student_old.reload
    assert_equal @classroom_a.id, @student_old.classroom_id, "생존자가 현재 학급 승계"
    assert_equal 1, @student_old.reports.count
  end

  test "교사 메뉴에서 계정 연동 화면으로 들어갈 수 있다" do
    login_as(@teacher_a)

    get teacher_students_path

    assert_response :success
    assert_includes response.body, "계정 연동"
    assert_includes response.body, teacher_account_links_path
  end

  test "다른 학급 학생을 NEW 로 지정하면 owned_student! 403" do
    other_new = User.create!(school: @school, classroom: @classroom_b, name: "남의반학생", password: "xpw123")
    login_as(@teacher_a)

    post teacher_account_links_path, params: { new_account_id: other_new.id, old_account_id: @student_old.id }

    assert_response :forbidden
    assert User.exists?(@student_old.id), "병합되지 않는다"
  end

  test "담임은 14일 안의 자기 학급 연동을 되돌린다" do
    merge = perform_merge!(@student_old, @student_new, @teacher_a)
    login_as(@teacher_a)

    post reverse_teacher_account_link_path(merge)

    assert_redirected_to teacher_account_links_path
    assert merge.reload.reversed_at, "되돌림 스탬프"
    assert User.exists?(@student_new.id), "placeholder 재생성"
  end

  test "14일이 지난 연동은 교사가 되돌릴 수 없다" do
    merge = perform_merge!(@student_old, @student_new, @teacher_a)
    merge.update_column(:created_at, 15.days.ago)
    login_as(@teacher_a)

    post reverse_teacher_account_link_path(merge)

    assert_redirected_to teacher_account_links_path
    assert_nil merge.reload.reversed_at, "창 밖 되돌리기 거부"
  end

  test "다른 담임의 연동은 되돌릴 수 없다(크로스학급 403)" do
    merge = perform_merge!(@student_old, @student_new, @teacher_a) # to_classroom = classroom_a
    login_as(@teacher_b)

    post reverse_teacher_account_link_path(merge)

    assert_response :forbidden
    assert_nil merge.reload.reversed_at
  end

  test "학생은 교사 연동 화면에 접근할 수 없다" do
    login_as(@student_new, password: "npw123")

    get teacher_account_links_path
    assert_response :forbidden
  end

  test "되돌리기 중 유니크 충돌은 500 이 아니라 alert 리다이렉트로 처리한다(ReversalError rescue)" do
    merge = perform_merge!(@student_old, @student_new, @teacher_a)
    # 생존자의 pre-merge tuple(old_classroom, "김이어")을 제3자가 점유 → 신원 복원 시 tuple 충돌.
    User.create!(school: @school, classroom: @old_classroom, name: "김이어", password: "sq1234")
    login_as(@teacher_a)

    post reverse_teacher_account_link_path(merge)

    assert_redirected_to teacher_account_links_path
    assert_nil merge.reload.reversed_at, "충돌로 트랜잭션 롤백 — 원자 클레임까지 원복(되돌림 미완료)"
  end

  private

  def perform_merge!(old, new, performer)
    Accounts::MergeService.new(old_account: old, new_account: new, performed_by: performer).call.account_merge
  end
end
