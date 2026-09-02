require "test_helper"

class BoardPostsTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "게시판통합초")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @teacher = User.create!(school: @school, classroom: @classroom, name: "게시판교사", role: :teacher, password: "password")
    @classroom.update!(teacher: @teacher)
    @author = User.create!(school: @school, classroom: @classroom, name: "글쓴이", password: "password")
    @peer = User.create!(school: @school, classroom: @classroom, name: "응원친구", password: "password")
    # 공유는 담임 승인(reviewed) 후에만 가능하다(ReportPolicy#share?). 이 파일의 관심사는
    # 공유 **이후**의 게시판·응원·스티커 동작이므로 승인본을 전제로 둔다. 게이트 자체는
    # report_policy_test.rb(4상태)와 아래 "검토 전에는 공유할 수 없다" 테스트가 지킨다.
    @report = Report.create!(user: @author, classroom: @classroom, book_title: "우수작 책",
                             body: "정말 좋은 독후감입니다.",
                             submitted_at: Time.current, reviewed: true, reviewed_at: Time.current)
  end

  test "검토 전 독후감은 작성자도 우수작으로 공유할 수 없다" do
    draft = Report.create!(user: @author, classroom: @classroom, book_title: "아직 낸 적 없는 책", body: "초안이에요.")
    login_as @author

    assert_no_difference "BoardPost.count" do
      post share_report_path(draft)
    end
    assert_not draft.reload.shared?
  end

  test "승인이 풀리는 재제출은 공유와 게시물을 함께 걷는다" do
    login_as @author
    post share_report_path(@report)
    assert @report.reload.shared?

    patch report_path(@report), params: { report: { body: "고쳐 쓴 본문이에요." } }

    assert_not @report.reload.shared?, "재제출로 미검토가 된 글이 게시판에 남아 있으면 안 된다"
    assert_nil BoardPost.find_by(report: @report)
  end

  test "author sharing a report creates a board post and marks it shared" do
    login_as @author
    assert_difference "BoardPost.count", 1 do
      post share_report_path(@report)
    end
    assert @report.reload.shared?
    assert_redirected_to board_post_path(BoardPost.find_by(report: @report))
  end

  test "share is a real toggle — sharing again unshares and removes the board post" do
    login_as @author
    post share_report_path(@report)
    assert @report.reload.shared?
    board_post = BoardPost.find_by(report: @report)

    assert_difference "BoardPost.count", -1 do
      post share_report_path(@report)
    end
    assert_not @report.reload.shared?, "다시 누르면 공유가 취소된다"
    assert_not BoardPost.exists?(board_post.id), "연결된 게시물이 파기된다"
    assert_redirected_to report_path(@report)
  end

  test "unsharing resets cheers_count and destroys cheers so the counter is not stale" do
    login_as @author
    post share_report_path(@report)
    board_post = BoardPost.find_by(report: @report)

    login_as @peer
    post board_post_cheers_path(board_post)
    assert_equal 1, @report.reload.cheers_count

    login_as @author
    post share_report_path(@report) # unshare
    assert_equal 0, @report.reload.cheers_count, "공유 취소 시 수동 카운터도 0 으로 초기화"
    assert_equal 0, Cheer.where(board_post_id: board_post.id).count, "응원 행도 cascade 삭제"
    assert_equal 0, ReadingStats.new(@author).cheers_received, "스탯 집계가 stale 하지 않다"
  end

  test "sharing again after unsharing recreates the board post" do
    login_as @author
    post share_report_path(@report) # share
    post share_report_path(@report) # unshare

    assert_difference "BoardPost.count", 1 do
      post share_report_path(@report) # re-share
    end
    assert @report.reload.shared?
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

  test "a concurrent duplicate cheer does not 500 and does not double-count" do
    board_post = BoardPost.create!(report: @report)
    login_as @peer
    post board_post_cheers_path(board_post), as: :turbo_stream
    assert_equal 1, @report.reload.cheers_count

    # 동시 더블클릭 재현: 유니크 검증은 통과했으나 DB 유니크 인덱스가 거부해
    # RecordNotUnique 가 나는 경쟁 상황. save 를 잠시 바꿔 강제로 재현한다.
    Cheer.class_eval do
      alias_method :__orig_save, :save
      def save(*)
        raise ActiveRecord::RecordNotUnique, "duplicate index"
      end
    end
    begin
      post board_post_cheers_path(board_post), as: :turbo_stream
      assert_response :success, "중복 응원이 500 을 내지 않는다"
    ensure
      Cheer.class_eval do
        remove_method :save
        alias_method :save, :__orig_save
        remove_method :__orig_save
      end
    end

    assert_equal 1, @report.reload.cheers_count, "중복 요청은 카운터를 재증가시키지 않는다"
    assert_equal 1, Cheer.where(board_post_id: board_post.id, user_id: @peer.id).count
  end

  test "a student cannot cheer a hidden board post" do
    hidden = BoardPost.create!(report: @report, hidden: true)
    login_as @peer
    assert_no_difference "Cheer.count" do
      post board_post_cheers_path(hidden), as: :turbo_stream
    end
    assert_response :forbidden
  end

  test "a student cannot place a sticker on a hidden board post" do
    hidden = BoardPost.create!(report: @report, hidden: true)
    login_as @peer
    assert_no_difference "Sticker.count" do
      post board_post_stickers_path(hidden),
           params: { sticker: { emoji: "👍", label: "멋져요", position: 0 } }, as: :turbo_stream
    end
    assert_response :forbidden
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

  test "board posts index paginates shared reports into 20-per-page slices" do
    25.times do |i|
      report = Report.create!(user: @author, classroom: @classroom, book_title: "우수작#{format('%02d', i)}", body: "본문")
      BoardPost.create!(report: report)
    end
    login_as @peer

    get board_posts_path
    assert_response :success
    assert_select "article", 20
    assert_match "다음", response.body

    get board_posts_path(page: 2)
    assert_response :success
    assert_select "article", 5
    assert_match "이전", response.body
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
end
