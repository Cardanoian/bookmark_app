# 총괄관리자 전용 베이스(P7.1). superadmin 만 접근 가능하며, 그 외 전 역할(교무관리자
# 포함)은 403 으로 차단한다 — /admin 정책 격리의 1차 게이트. 모든 Admin::* 컨트롤러가 상속.
class Admin::BaseController < ApplicationController
  layout "admin"

  before_action :require_superadmin!

  private

  def require_superadmin!
    raise Pundit::NotAuthorizedError unless Current.user&.superadmin?
  end
end
