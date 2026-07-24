# 문장 스티커 동료평가 정책(P5.3). 로그인 학생이면 스티커를 붙일 수 있다.
# 단, 해당 report 의 게시물이 학생에게 보이는(숨김 아님) 경우에만 가능하다(§2.8).
class StickerPolicy < ApplicationPolicy
  def create?
    return false unless user&.student?

    board_post = record.report&.board_post
    board_post.present? && BoardPostPolicy.new(user, board_post).show?
  end
end
