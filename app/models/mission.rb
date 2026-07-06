# 학급 단위 독서 미션. 참여 report(mission_id)가 진화/뱃지 조건에 반영된다.
class Mission < ApplicationRecord
  belongs_to :classroom
  belongs_to :book, optional: true
end
