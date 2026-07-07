# 응원 정책(P5.3). 로그인 학생이면 응원 가능, 취소는 본인 응원만.
# 단, 게시물이 학생에게 보이는(숨김 아님) 경우에만 응원할 수 있다(§2.8).
class CheerPolicy < ApplicationPolicy
  def create?
    return false unless user&.student?

    board_post = record.board_post
    board_post.present? && BoardPostPolicy.new(user, board_post).show?
  end

  def destroy?
    return false unless user

    record.user_id == user.id
  end
end
