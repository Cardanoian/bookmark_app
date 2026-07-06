# 시즌(랭킹 리셋 주기). 전역/학교 범위.
class Season < ApplicationRecord
  enum :scope, { global: 0, school: 1 }

  belongs_to :school, optional: true
end
