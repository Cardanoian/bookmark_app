# 랭킹 정책(P4.10). 로그인 사용자면 열람 가능.
class RankingPolicy < ApplicationPolicy
  def index?
    user.present?
  end
end
