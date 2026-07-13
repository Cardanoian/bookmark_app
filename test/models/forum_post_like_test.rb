require "test_helper"

# 게시판 글 좋아요(ForumPostLike, P5.4). (forum_post, user) 유일성 + likes_count counter_cache 증감.
class ForumPostLikeTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "좋아요학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @user = User.create!(school: @school, classroom: @classroom, name: "좋아요학생", password: "password")
    @topic = Topic.create!(title: "좋아요주제", scope: :classroom, classroom: @classroom)
    @post = ForumPost.create!(topic: @topic, user: @user, text: "좋아요 대상 글")
  end

  test "a second like from the same user on the same post is invalid (uniqueness)" do
    ForumPostLike.create!(forum_post: @post, user: @user)
    duplicate = ForumPostLike.new(forum_post: @post, user: @user)

    assert_not duplicate.valid?
    assert duplicate.errors[:user_id].any?
  end

  test "creating a like increments the forum post's likes_count counter cache" do
    assert_difference -> { @post.reload.likes_count }, 1 do
      ForumPostLike.create!(forum_post: @post, user: @user)
    end
  end

  test "destroying a like decrements the forum post's likes_count counter cache" do
    like = ForumPostLike.create!(forum_post: @post, user: @user)
    assert_equal 1, @post.reload.likes_count

    assert_difference -> { @post.reload.likes_count }, -1 do
      like.destroy
    end
  end
end
