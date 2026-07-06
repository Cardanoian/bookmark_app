# 전역/학교 단위 챌린지. 참여 report(challenge_id)가 진화/뱃지 조건에 반영된다.
class Challenge < ApplicationRecord
  enum :scope, { global: 0, school: 1 }

  belongs_to :school, optional: true
end
