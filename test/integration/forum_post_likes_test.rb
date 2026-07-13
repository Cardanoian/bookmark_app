require "test_helper"

# 게시판 글 좋아요(ForumPostLike) e2e — 좋아요 생성/토글 취소, 1인 1좋아요(무해 재클릭),
# 학급 경계 차단(forum_post_policy → TopicPolicy#show? 위임), 로그인 게이트.
class ForumPostLikesTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "좋아요통합초")
    @class1 = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @class2 = Classroom.create!(school: @school, grade: 5, class_no: 2)
    @student1 = User.create!(school: @school, classroom: @class1, name: "좋아요학생1", password: "password")
    @outsider = User.create!(school: @school, classroom: @class2, name: "좋아요학생2", password: "password")

    @topic = Topic.create!(scope: :classroom, classroom: @class1, title: "좋아요 토론")
    @message = @topic.forum_posts.create!(user: @student1, text: "좋아요 대상 글")
  end

  test "a boundary-in user liking a post increments likes_count and redirects to the topic" do
    login_as @student1
    assert_difference -> { @message.reload.likes_count }, 1 do
      post forum_post_like_path(@message)
    end
    assert_redirected_to topic_path(@topic)
  end

  test "deleting the like toggles it off and decrements likes_count back to zero" do
    login_as @student1
    post forum_post_like_path(@message)
    assert_equal 1, @message.reload.likes_count

    assert_difference -> { @message.reload.likes_count }, -1 do
      delete forum_post_like_path(@message)
    end
    assert_equal 0, @message.reload.likes_count
    assert_not @message.liked_by?(@student1)
  end

  test "liking the same post twice is a harmless no-op (no 500, likes_count stays at 1)" do
    login_as @student1
    post forum_post_like_path(@message)
    assert_equal 1, @message.reload.likes_count

    assert_no_difference -> { @message.reload.likes_count } do
      post forum_post_like_path(@message)
    end
    assert_redirected_to topic_path(@topic), "중복 좋아요는 500 없이 토론방으로 정상 리다이렉트"
    assert_equal 1, @message.reload.likes_count
  end

  test "a student outside the topic's classroom boundary cannot like the post" do
    login_as @outsider
    assert_no_difference -> { @message.reload.likes_count } do
      post forum_post_like_path(@message)
    end
    assert_response :forbidden
  end

  test "an unauthenticated request to like a post redirects to login" do
    assert_no_difference -> { @message.reload.likes_count } do
      post forum_post_like_path(@message)
    end
    assert_redirected_to new_session_path
  end

  def login_as(user)
    post session_path, params: {
      school_id: user.school_id, classroom_id: user.classroom_id,
      name: user.name, password: "password"
    }
  end
end
