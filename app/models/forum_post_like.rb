# 게시판 글 좋아요(👍, P5.4). forum_post 당 사용자 1인 1좋아요(unique).
# forum_post.likes_count 를 counter_cache 로 증감한다.
class ForumPostLike < ApplicationRecord
  belongs_to :forum_post, counter_cache: :likes_count
  belongs_to :user

  validates :user_id, uniqueness: { scope: :forum_post_id }
end
