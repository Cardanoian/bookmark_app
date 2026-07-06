# 우수작 게시판 게시물(P5.3). 공유된 report 를 게시판에 노출한다. report 당 1개.
class BoardPost < ApplicationRecord
  belongs_to :report
  belongs_to :hidden_by, class_name: "User", optional: true
  has_many :cheers, dependent: :destroy

  validates :report_id, uniqueness: true

  scope :visible, -> { where(hidden: false) }

  # 응원 수는 report 의 카운터 캐시(cheers_count)를 사용한다.
  delegate :cheers_count, to: :report

  def cheered_by?(user)
    return false unless user

    cheers.exists?(user_id: user.id)
  end
end
