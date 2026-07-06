# 학생 획득 뱃지. unique(user_id, badge_id) — 중복 획득 방지.
class UserBadge < ApplicationRecord
  belongs_to :user
  belongs_to :badge

  validates :badge_id, uniqueness: { scope: :user_id }
end
