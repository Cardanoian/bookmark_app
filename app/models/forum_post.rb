# 토론 글(P5.4). 좋아요는 forum_post_likes(1인 1좋아요)로 counter_cache(likes_count).
class ForumPost < ApplicationRecord
  belongs_to :topic, counter_cache: true
  belongs_to :user

  has_many :forum_post_likes, dependent: :destroy

  validates :text, presence: true

  scope :visible, -> { where(hidden: false) }

  # 사용자가 이 글을 좋아요했는지 여부.
  def liked_by?(user)
    user && forum_post_likes.exists?(user_id: user.id)
  end
end
