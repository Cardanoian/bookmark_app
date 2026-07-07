require "test_helper"

class TopicsTest < ActionDispatch::IntegrationTest
  setup do
    @school = School.create!(name: "토론통합초")
    @class1 = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @class2 = Classroom.create!(school: @school, grade: 5, class_no: 2)
    @student1 = User.create!(school: @school, classroom: @class1, name: "토론학생1", password: "password")
    @student2 = User.create!(school: @school, classroom: @class2, name: "토론학생2", password: "password")
  end

  test "student creates a classroom-scope topic bound to their classroom" do
    login_as @student1
    assert_difference "Topic.count", 1 do
      post topics_path, params: { topic: { title: "우리 반 토론", scope: "classroom" } }
    end
    topic = Topic.last
    assert topic.classroom?
    assert_equal @class1.id, topic.classroom_id
    assert_nil topic.school_id
    assert_redirected_to topic_path(topic)
  end

  test "student posts a forum message in their own classroom topic" do
    topic = Topic.create!(scope: :classroom, classroom: @class1, title: "토론")
    login_as @student1
    assert_difference "ForumPost.count", 1 do
      post topic_forum_posts_path(topic), params: { forum_post: { text: "제 생각을 나눠요." } }
    end
    assert_redirected_to topic_path(topic)
  end

  test "student cannot post in another classroom's topic (boundary)" do
    topic = Topic.create!(scope: :classroom, classroom: @class2, title: "2반 토론")
    login_as @student1
    assert_no_difference "ForumPost.count" do
      post topic_forum_posts_path(topic), params: { forum_post: { text: "경계 밖" } }
    end
    assert_response :forbidden
  end

  test "student cannot view another classroom's topic (boundary)" do
    topic = Topic.create!(scope: :classroom, classroom: @class2, title: "2반 토론")
    login_as @student1
    get topic_path(topic)
    assert_response :forbidden
  end

  test "topics index shows the forum post count from the counter cache" do
    topic = Topic.create!(scope: :classroom, classroom: @class1, title: "카운트 토론")
    2.times { |i| topic.forum_posts.create!(user: @student1, text: "글 #{i}") }
    login_as @student1

    get topics_path
    assert_response :success
    assert_match "글 2개", response.body
  end

  test "topics index paginates classroom topics into 20-per-page slices" do
    25.times { |i| Topic.create!(scope: :classroom, classroom: @class1, title: "토픽#{format('%02d', i)}") }
    login_as @student1

    get topics_path
    assert_response :success
    assert_select "article", 20
    assert_match "다음", response.body

    get topics_path(page: 2)
    assert_response :success
    assert_select "article", 5
    assert_match "이전", response.body
  end

  test "forum post like increments likes_count" do
    topic = Topic.create!(scope: :classroom, classroom: @class1, title: "토론")
    message = topic.forum_posts.create!(user: @student1, text: "좋아요 대상 글")
    assert_difference -> { message.reload.likes_count }, 1 do
      message.like!
    end
  end

  def login_as(user)
    post session_path, params: {
      school_id: user.school_id, classroom_id: user.classroom_id,
      name: user.name, password: "password"
    }
  end
end
