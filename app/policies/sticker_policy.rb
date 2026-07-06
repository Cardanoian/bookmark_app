# 문장 스티커 동료평가 정책(P5.3). 로그인 학생이면 스티커를 붙일 수 있다.
class StickerPolicy < ApplicationPolicy
  def create?
    user&.student?
  end
end
