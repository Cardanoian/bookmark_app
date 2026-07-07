# topics#index 의 `forum_posts.count` per-topic N+1(§3.3, 성능D) 을 제거하기 위한
# 카운터 캐시 컬럼. add_column 으로 기존 행은 0 이 되므로, 상관 서브쿼리로 실제
# 글 수를 백필한다. 앱 모델(Topic) 대신 raw SQL 로 백필해 마이그레이션을 모델
# 스코프와 분리한다 — 새 DB 에서 재실행해도 결정적으로 전 토픽을 정확히 채운다.
class AddForumPostsCountToTopics < ActiveRecord::Migration[8.1]
  def up
    add_column :topics, :forum_posts_count, :integer, default: 0, null: false

    execute(<<~SQL.squish)
      UPDATE topics
      SET forum_posts_count = (
        SELECT COUNT(*) FROM forum_posts WHERE forum_posts.topic_id = topics.id
      )
    SQL
  end

  def down
    remove_column :topics, :forum_posts_count
  end
end
