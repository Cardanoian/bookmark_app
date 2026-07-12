require "test_helper"

# 토론 글(#5 미테스트 모델 보강). text 검증·visible 스코프·topic counter_cache·like!.
class ForumPostTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "토론학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @user = User.create!(school: @school, classroom: @classroom, name: "토론학생", password: "password")
    @topic = Topic.create!(title: "토론주제", scope: :classroom, classroom: @classroom)
  end

  test "text is required" do
    post = ForumPost.new(topic: @topic, user: @user)
    assert_not post.valid?
    assert post.errors[:text].any?
  end

  test "visible scope excludes hidden posts" do
    shown = ForumPost.create!(topic: @topic, user: @user, text: "보이는글")
    hidden = ForumPost.create!(topic: @topic, user: @user, text: "숨긴글", hidden: true)

    visible = ForumPost.visible
    assert_includes visible, shown
    assert_not_includes visible, hidden
  end

  test "creating a post bumps the topic counter cache" do
    assert_difference -> { @topic.reload.forum_posts_count }, 1 do
      ForumPost.create!(topic: @topic, user: @user, text: "카운터글")
    end
  end

  test "like! increments likes_count" do
    post = ForumPost.create!(topic: @topic, user: @user, text: "좋아요글")
    assert_equal 0, post.likes_count
    post.like!
    assert_equal 1, post.reload.likes_count
  end
end
