require "test_helper"

# 계정 연동 총괄 보조(account_linking_seasons_plan §Phase 4) — 감사 요약(PII 미노출)·시간창 무제한
# 되돌리기·임의 병합·역할 격리.
class AdminAccountLinksTest < ActionDispatch::IntegrationTest
  setup do
    seed_monster_species!
    @school = School.create!(name: "총괄연동초")
    current = Classroom.current_academic_year
    @old_classroom = Classroom.create!(school: @school, grade: 3, class_no: 1, academic_year: current - 1)
    @new_classroom = Classroom.create!(school: @school, grade: 4, class_no: 1, academic_year: current)
    @admin = User.create!(school: @school, name: "총괄", role: :superadmin, email: "admin@example.com", password: "password")
    @old = User.create!(school: @school, classroom: @old_classroom, name: "박이어", password: "opw123")
    @new = User.create!(school: @school, classroom: @new_classroom, name: "박이어", password: "npw123")
    Report.create!(user: @old, classroom: @old_classroom, book_title: "작년책", reviewed: true)
  end

  test "총괄은 감사 목록을 보되 snapshot PII(비밀번호 다이제스트)는 노출하지 않는다" do
    digest = @old.password_digest
    perform_merge!(@old, @new, @admin)
    login_as(@admin)

    get admin_account_links_path

    assert_response :success
    assert_includes response.body, @old.reload.name
    assert_not_includes response.body, digest, "snapshot 의 password_digest 를 화면에 덤프하지 않는다"
  end

  test "총괄은 14일이 지난 연동도 되돌린다(시간창 무제한)" do
    merge = perform_merge!(@old, @new, @admin)
    merge.update_column(:created_at, 60.days.ago)
    login_as(@admin)

    post reverse_admin_account_link_path(merge)

    assert_redirected_to admin_account_links_path
    assert merge.reload.reversed_at
    assert User.exists?(@new.id), "되돌리기로 placeholder 재생성"
  end

  test "총괄은 임의 병합을 수행한다" do
    login_as(@admin)

    post admin_account_links_path, params: { old_account_id: @old.id, new_account_id: @new.id }

    assert_redirected_to admin_account_links_path
    assert_not User.exists?(@new.id)
    assert_equal @new_classroom.id, @old.reload.classroom_id
  end

  test "비총괄(교사)은 감사에 접근할 수 없다" do
    teacher = User.create!(school: @school, classroom: @new_classroom, name: "교사",
                           role: :teacher, email: "t@example.com", password: "password")
    login_as(teacher)

    get admin_account_links_path
    assert_response :forbidden
  end

  private

  def perform_merge!(old, new, performer)
    Accounts::MergeService.new(old_account: old, new_account: new, performed_by: performer).call.account_merge
  end
end
