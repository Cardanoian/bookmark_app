# 응원(👏, P5.3). 게시물당 사용자 1인 1회.
class Cheer < ApplicationRecord
  belongs_to :board_post
  belongs_to :user

  validates :user_id, uniqueness: { scope: :board_post_id }
end
