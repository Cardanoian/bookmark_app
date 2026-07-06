require "test_helper"

# P7.6 모더레이션: 숨김/해제 + 숨김 콘텐츠는 학생 화면 비노출, 관리자에게는 노출.
class AdminModerationTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "모더학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @superadmin = User.create!(name: "총괄", role: :superadmin, password: "password")
    @student = User.create!(school: @school, classroom: @classroom, name: "학생모더", role: :student, password: "password")

    report = Report.create!(user: @student, classroom: @classroom, book_title: "숨김대상책", body: "본문내용", shared: true)
    @board_post = BoardPost.create!(report: report)

    @topic = Topic.create!(title: "토픽제목", scope: :classroom, classroom: @classroom)
    @forum_post = ForumPost.create!(topic: @topic, user: @student, text: "숨김대상토론글")
  end

  test "hide sets hidden and records hidden_by on board_post" do
    login_as @superadmin
    post hide_admin_moderation_path(@board_post, kind: "board_post")
    @board_post.reload
    assert @board_post.hidden?
    assert_equal @superadmin.id, @board_post.hidden_by_id
  end

  test "unhide clears hidden" do
    @board_post.update!(hidden: true)
    login_as @superadmin
    post unhide_admin_moderation_path(@board_post, kind: "board_post")
    assert_not @board_post.reload.hidden?
  end

  test "hide works on a forum_post" do
    login_as @superadmin
    post hide_admin_moderation_path(@forum_post, kind: "forum_post")
    assert @forum_post.reload.hidden?
  end

  test "a hidden board_post is excluded from the student index but visible to admin" do
    login_as @student
    get board_posts_path
    assert_match "숨김대상책", response.body

    login_as @superadmin
    post hide_admin_moderation_path(@board_post, kind: "board_post")
    get admin_moderation_index_path
    assert_match "숨김대상책", response.body

    login_as @student
    get board_posts_path
    assert_no_match "숨김대상책", response.body
  end

  test "a hidden forum_post is excluded from the student-facing topic view" do
    login_as @student
    get topic_path(@topic)
    assert_match "숨김대상토론글", response.body

    login_as @superadmin
    post hide_admin_moderation_path(@forum_post, kind: "forum_post")

    login_as @student
    get topic_path(@topic)
    assert_no_match "숨김대상토론글", response.body
  end

  private

  def login_as(user)
    post session_path, params: {
      school_id: user.school_id, classroom_id: user.classroom_id,
      name: user.name, password: "password"
    }
  end
end
