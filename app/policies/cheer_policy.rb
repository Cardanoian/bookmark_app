# 응원 정책(P5.3). 로그인 학생이면 응원 가능, 취소는 본인 응원만.
class CheerPolicy < ApplicationPolicy
  def create?
    user&.student?
  end

  def destroy?
    return false unless user

    record.user_id == user.id
  end
end
