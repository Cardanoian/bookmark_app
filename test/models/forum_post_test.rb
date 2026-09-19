require "test_helper"

# 토론 글(#5 미테스트 모델 보강). text 검증·visible 스코프·topic counter_cache.
# (좋아요 counter_cache 는 forum_post_like_test.rb 가 증감 양방향으로 검증.)
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

  test "a debate post requires a stance" do
    debate = Topic.create!(title: "찬반주제", scope: :classroom, classroom: @classroom, kind: :debate)
    post = ForumPost.new(topic: debate, user: @user, text: "입장 없는 글")
    assert_not post.valid?
    assert_includes post.errors.full_messages, "찬성인지 반대인지 골라 주세요."

    %w[pro con].each do |stance|
      post.stance = stance
      assert post.valid?, "#{stance} 입장은 저장할 수 있어야 합니다"
    end
  end

  # 자유 의견 토론방에는 입장 칸이 없으므로, 조작해 보낸 입장은 저장하지 않는다.
  test "a free-discussion post cannot carry a stance" do
    post = ForumPost.new(topic: @topic, user: @user, text: "자유 의견 글", stance: :pro)
    assert_not post.valid?
    assert_includes post.errors.full_messages, "자유 의견 토론방에서는 찬성·반대를 고르지 않아요."
  end

  # 방식과 어긋난 옛 글(찬반 토론방의 입장 없는 글)도 숨김·해제는 막히지 않는다(아동 안전 경로).
  test "a stance-less post in a debate topic can still be hidden" do
    debate = Topic.create!(title: "찬반주제", scope: :classroom, classroom: @classroom, kind: :debate)
    post = ForumPost.new(topic: debate, user: @user, text: "입장 없는 옛 글")
    post.save!(validate: false)

    assert_nothing_raised { post.update!(hidden: true) }
    assert post.reload.hidden?
  end

  test "an unknown stance is a validation error instead of an exception" do
    debate = Topic.create!(title: "찬반주제", scope: :classroom, classroom: @classroom, kind: :debate)
    post = ForumPost.new(topic: debate, user: @user, text: "조작한 입장")
    assert_nothing_raised { post.stance = "bogus" }
    assert_not post.valid?
    assert post.errors.of_kind?(:stance, :inclusion)
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
end
