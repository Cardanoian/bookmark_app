require "test_helper"

class BoardPostsTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "게시판통합초")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @teacher = User.create!(school: @school, classroom: @classroom, name: "게시판교사", role: :teacher, password: "password")
    @classroom.update!(teacher: @teacher)
    @author = User.create!(school: @school, classroom: @classroom, name: "글쓴이", password: "password")
    @peer = User.create!(school: @school, classroom: @classroom, name: "응원친구", password: "password")
    @report = Report.create!(user: @author, classroom: @classroom, book_title: "우수작 책", body: "정말 좋은 독후감입니다.")
  end

  test "author sharing a report creates a board post and marks it shared" do
    login_as @author
    assert_difference "BoardPost.count", 1 do
      post share_report_path(@report)
    end
    assert @report.reload.shared?
    assert_redirected_to board_post_path(BoardPost.find_by(report: @report))
  end

  test "sharing is idempotent — one board post per report" do
    login_as @author
    post share_report_path(@report)
    assert_no_difference "BoardPost.count" do
      post share_report_path(@report)
    end
  end

  test "a non-author non-teacher student cannot share" do
    login_as @peer
    assert_no_difference "BoardPost.count" do
      post share_report_path(@report)
    end
    assert_response :forbidden
  end

  test "the classroom teacher can share a student report" do
    login_as @teacher
    assert_difference "BoardPost.count", 1 do
      post share_report_path(@report)
    end
  end

  test "cheer is one per user and increments report.cheers_count" do
    board_post = BoardPost.create!(report: @report)
    login_as @peer

    assert_difference -> { @report.reload.cheers_count }, 1 do
      assert_difference "Cheer.count", 1 do
        post board_post_cheers_path(board_post)
      end
    end

    assert_no_difference [ "Cheer.count" ] do
      post board_post_cheers_path(board_post)
    end
    assert_equal 1, @report.reload.cheers_count
  end

  test "removing a cheer decrements report.cheers_count" do
    board_post = BoardPost.create!(report: @report)
    login_as @peer
    post board_post_cheers_path(board_post)
    cheer = board_post.cheers.find_by(user: @peer)

    assert_difference -> { @report.reload.cheers_count }, -1 do
      delete board_post_cheer_path(board_post, cheer)
    end
    assert_equal 0, @report.reload.cheers_count
  end

  test "a student can place a sentence sticker on a shared report" do
    board_post = BoardPost.create!(report: @report)
    login_as @peer

    assert_difference "Sticker.count", 1 do
      post board_post_stickers_path(board_post),
           params: { sticker: { emoji: "👍", label: "멋져요", position: 0 } }
    end

    sticker = Sticker.last
    assert_equal @peer, sticker.by_user
    assert_equal @report, sticker.report
  end

  test "hidden board posts are excluded from the index for students" do
    visible = BoardPost.create!(report: @report)
    hidden_report = Report.create!(user: @author, classroom: @classroom, book_title: "숨김글", body: "숨겨진 글")
    hidden = BoardPost.create!(report: hidden_report, hidden: true)

    login_as @peer
    get board_posts_path
    assert_response :success
    assert_select "##{ActionView::RecordIdentifier.dom_id(visible)}"
    assert_select "##{ActionView::RecordIdentifier.dom_id(hidden)}", count: 0
  end

  def login_as(user)
    post session_path, params: {
      school_id: user.school_id, classroom_id: user.classroom_id,
      name: user.name, password: "password"
    }
  end
end
