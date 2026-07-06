# 토론방(P5.4). classroom/school 스코프로 학급·학교 단위 토론을 구분한다.
class Topic < ApplicationRecord
  enum :scope, { classroom: 0, school: 1 }, default: :classroom

  belongs_to :classroom, optional: true
  belongs_to :school, optional: true
  belongs_to :book, optional: true
  has_many :forum_posts, dependent: :destroy

  validates :title, presence: true

  scope :visible, -> { where(hidden: false) }
end
