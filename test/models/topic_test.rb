require "test_helper"

# 토론방 forum_posts_count 카운터 캐시(§3.3). topics#index 의 per-topic N+1 을
# 제거하기 위해 forum_post → topic 에 counter_cache 를 걸었다.
class TopicTest < ActiveSupport::TestCase
  setup do
    @school = School.create!(name: "카운터캐시학교")
    @classroom = Classroom.create!(school: @school, grade: 5, class_no: 1)
    @student = User.create!(school: @school, classroom: @classroom, name: "카운터학생", password: "password")
    @topic = Topic.create!(scope: :classroom, classroom: @classroom, title: "카운터 토론")
  end

  test "creating a forum post increments the topic counter cache" do
    assert_difference -> { @topic.reload.forum_posts_count }, 1 do
      @topic.forum_posts.create!(user: @student, text: "첫 글")
    end
  end

  test "destroying a forum post decrements the topic counter cache" do
    post = @topic.forum_posts.create!(user: @student, text: "지울 글")
    assert_difference -> { @topic.reload.forum_posts_count }, -1 do
      post.destroy
    end
  end

  # 마이그레이션 백필 정합: 카운터 없이 쌓인 기존 데이터를 재현한 뒤 재계산하면
  # 실제 글 수와 일치해야 한다(= UPDATE ... COUNT(*) 백필과 동일 결과).
  test "reset_counters recomputes forum_posts_count to match actual rows" do
    3.times { |i| @topic.forum_posts.create!(user: @student, text: "글 #{i}") }
    @topic.update_column(:forum_posts_count, 0)

    Topic.reset_counters(@topic.id, :forum_posts)

    assert_equal 3, @topic.reload.forum_posts_count
    assert_equal @topic.forum_posts.count, @topic.forum_posts_count
  end
end
