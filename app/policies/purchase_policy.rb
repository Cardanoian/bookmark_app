# 구매 정책(P4.8). 학생 본인만 구매 가능.
class PurchasePolicy < ApplicationPolicy
  def create?
    user&.student?
  end
end
