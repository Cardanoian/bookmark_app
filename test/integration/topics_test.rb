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

  # 없는 범위 값(조작한 topic[scope]=bogus)은 500 이 아니라 만들지 않고 목록으로 돌려보낸다.
  test "an unknown scope is rejected instead of raising" do
    login_as @student1
    assert_no_difference "Topic.count" do
      post topics_path, params: { topic: { title: "조작한 범위", scope: "bogus" } }
    end
    assert_redirected_to topics_path
  end

  test "student opens a debate topic" do
    login_as @student1
    assert_difference "Topic.count", 1 do
      post topics_path, params: { topic: { title: "찬반 토론", scope: "classroom", kind: "debate" } }
    end
    assert Topic.last.debate?
  end

  # 없는 방식 값(조작한 topic[kind]=bogus)도 500 이 아니라 만들지 않고 목록으로 돌려보낸다.
  test "an unknown kind is rejected instead of raising" do
    login_as @student1
    assert_no_difference "Topic.count" do
      post topics_path, params: { topic: { title: "조작한 방식", scope: "classroom", kind: "bogus" } }
    end
    assert_redirected_to topics_path
  end

  test "topic creation forms offer the discussion kind" do
    login_as @student1
    get topics_path
    assert_select "select[name='topic[kind]'] option[value='free']", text: "자유 의견"
    assert_select "select[name='topic[kind]'] option[value='debate']", text: "찬반 토론"
  end

  test "student posts a stance in a debate topic" do
    topic = Topic.create!(scope: :classroom, classroom: @class1, title: "찬반", kind: :debate)
    login_as @student1
    assert_difference "ForumPost.count", 1 do
      post topic_forum_posts_path(topic), params: { forum_post: { text: "저는 찬성해요.", stance: "pro" } }
    end
    assert ForumPost.last.pro?
    assert_redirected_to topic_path(topic)
  end

  test "a debate post without a stance is not saved" do
    topic = Topic.create!(scope: :classroom, classroom: @class1, title: "찬반", kind: :debate)
    login_as @student1
    assert_no_difference "ForumPost.count" do
      post topic_forum_posts_path(topic), params: { forum_post: { text: "입장을 안 골랐어요.", stance: "" } }
    end
    assert_redirected_to topic_path(topic)
    assert_equal "찬성인지 반대인지 골라 주세요.", flash[:alert]
  end

  # 자유 의견 토론방에는 입장 칸이 없으므로, 조작해 보낸 입장은 저장하지 않는다(500 도 아니다).
  test "a stance forged into a free topic is not saved" do
    topic = Topic.create!(scope: :classroom, classroom: @class1, title: "자유")
    login_as @student1
    assert_no_difference "ForumPost.count" do
      post topic_forum_posts_path(topic), params: { forum_post: { text: "조작한 입장", stance: "pro" } }
    end
    assert_redirected_to topic_path(topic)
  end

  test "an unknown stance in a debate topic is rejected instead of raising" do
    topic = Topic.create!(scope: :classroom, classroom: @class1, title: "찬반", kind: :debate)
    login_as @student1
    assert_no_difference "ForumPost.count" do
      post topic_forum_posts_path(topic), params: { forum_post: { text: "조작한 입장", stance: "bogus" } }
    end
    assert_redirected_to topic_path(topic)
  end

  # 찬반 토론은 같은 입장끼리 모은 두 칸(찬성·반대)으로 보이고, 칸 상단에 입장 이름이 나온다.
  test "debate topic groups posts into pro and con sections" do
    topic = Topic.create!(scope: :classroom, classroom: @class1, title: "찬반", kind: :debate)
    topic.forum_posts.create!(user: @student1, text: "찬성하는 까닭", stance: :pro)
    topic.forum_posts.create!(user: @student1, text: "또 찬성하는 까닭", stance: :pro)
    topic.forum_posts.create!(user: @student1, text: "반대하는 까닭", stance: :con)
    login_as @student1

    get topic_path(topic)
    assert_response :success
    assert_select "#stance_pro h2", text: /찬성/
    assert_select "#stance_con h2", text: /반대/
    assert_select "#stance_pro article", 2
    assert_select "#stance_pro article", text: /찬성하는 까닭/
    assert_select "#stance_con article", 1
    assert_select "#stance_con article", text: /반대하는 까닭/
    assert_select "#stance_none_heading", 0
    # lg(1024px) 이상은 좌우 두 칸, 그보다 좁으면 위아래 — 찬성 칸이 먼저 온다.
    assert_select "div.grid.lg\\:grid-cols-2 > section", 2
    assert_equal %w[stance_pro stance_con], css_select("div.grid.lg\\:grid-cols-2 > section").map { |node| node["id"] }
    assert_select ".badge", text: "찬반 토론"
    assert_select "input[type=radio][name='forum_post[stance]']", 2
    assert_select "input[type=radio][name='forum_post[stance]'][required]", 2
  end

  test "debate topic shows an empty message in a side with no posts" do
    topic = Topic.create!(scope: :classroom, classroom: @class1, title: "찬반", kind: :debate)
    topic.forum_posts.create!(user: @student1, text: "찬성하는 까닭", stance: :pro)
    login_as @student1

    get topic_path(topic)
    assert_select "#stance_con", text: /아직 반대 의견이 없어요/
  end

  # 자유 의견 토론방은 지금처럼 한 줄 목록이고 입장 칸·입장 선택이 없다.
  test "free topic keeps the single list without stance sections" do
    topic = Topic.create!(scope: :classroom, classroom: @class1, title: "자유")
    topic.forum_posts.create!(user: @student1, text: "자유롭게 쓴 글")
    login_as @student1

    get topic_path(topic)
    assert_response :success
    assert_select "#stance_pro", 0
    assert_select "#stance_con", 0
    assert_select "input[name='forum_post[stance]']", 0
    assert_select "article", text: /자유롭게 쓴 글/
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
      ForumPostLike.create!(forum_post: message, user: @student1)
    end
  end
end
