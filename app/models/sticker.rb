# 문장 스티커 동료평가(P5.3). report 본문 위치(position)에 붙는 이모지/라벨.
class Sticker < ApplicationRecord
  belongs_to :report
  belongs_to :by_user, class_name: "User"

  validates :emoji, presence: true
end
