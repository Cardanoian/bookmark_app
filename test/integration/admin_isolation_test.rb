require "test_helper"

# P7.1 정책 격리 게이트(핵심): /admin 은 superadmin 전용. school_admin(교무관리자)을 포함한
# 모든 비-superadmin 역할은 모든 /admin 라우트에서 403 을 받아야 한다.
class AdminIsolationTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "격리학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)

    @superadmin  = User.create!(name: "총괄관리자", role: :superadmin, password: "password")
    @school_admin = User.create!(school: @school, name: "교무관리자", role: :school_admin, password: "password")
    @teacher     = User.create!(school: @school, classroom: @classroom, name: "담임교사", role: :teacher, password: "password")
    @librarian   = User.create!(school: @school, name: "사서선생", role: :librarian, password: "password")
    @student     = User.create!(school: @school, classroom: @classroom, name: "홍길동", role: :student, password: "password")

    # 모더레이션·사용자 대상 레코드(변경 액션 격리 검증용).
    @target = User.create!(school: @school, classroom: @classroom, name: "대상학생", role: :student, password: "password")
    report = Report.create!(user: @student, classroom: @classroom, book_title: "책", body: "본문")
    @board_post = BoardPost.create!(report: report)
  end

  # 모든 관리자 GET 라우트 그룹(analytics/schools/users/books/quizzes/badges/
  # monster_species/moderation/settings/export). 상점 아이템은 PR7 에서 제거됨.
  def admin_get_paths
    [
      admin_root_path,
      admin_schools_path,
      admin_users_path,
      admin_books_path,
      admin_recommendation_imports_path,
      admin_quizzes_path,
      admin_badges_path,
      admin_monster_species_index_path,
      admin_moderation_index_path,
      admin_settings_path,
      admin_analytics_export_path
    ]
  end

  test "superadmin reaches every admin GET route" do
    login_as @superadmin
    admin_get_paths.each do |path|
      get path
      assert_response :success, "superadmin expected 200 at #{path} (got #{response.status})"
    end
  end

  test "every non-superadmin role is forbidden on every admin GET route" do
    [ @school_admin, @teacher, @librarian, @student ].each do |user|
      login_as user
      admin_get_paths.each do |path|
        get path
        assert_response :forbidden, "#{user.role} expected 403 at #{path} (got #{response.status})"
      end
    end
  end

  test "school_admin is forbidden from admin mutating routes" do
    login_as @school_admin

    post suspend_admin_user_path(@target)
    assert_response :forbidden
    patch role_admin_user_path(@target), params: { role: "teacher" }
    assert_response :forbidden
    post hide_admin_moderation_path(@board_post, kind: "board_post")
    assert_response :forbidden
    patch admin_settings_path, params: { seasonal_banner: "해킹" }
    assert_response :forbidden

    assert_not @target.reload.suspended?
    assert_not @board_post.reload.hidden?
  end

  test "superadmin can perform admin mutating routes" do
    login_as @superadmin

    post suspend_admin_user_path(@target)
    assert_response :redirect
    assert @target.reload.suspended?

    post hide_admin_moderation_path(@board_post, kind: "board_post")
    assert_response :redirect
    assert @board_post.reload.hidden?
  end

  private
end
