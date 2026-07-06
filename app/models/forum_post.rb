# 토론 글(P5.4). likes_count 는 좋아요 카운터.
class ForumPost < ApplicationRecord
  belongs_to :topic
  belongs_to :user

  validates :text, presence: true

  scope :visible, -> { where(hidden: false) }

  # 좋아요 1회 반영(카운터 증가).
  def like!
    increment!(:likes_count)
  end
end
