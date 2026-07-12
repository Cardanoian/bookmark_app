# 총괄관리자 전용 베이스(P7.1). superadmin 만 접근 가능하며, 그 외 전 역할(교무관리자
# 포함)은 403 으로 차단한다 — /admin 정책 격리의 1차 게이트. 모든 Admin::* 컨트롤러가 상속.
class Admin::BaseController < ApplicationController
  layout "admin"

  before_action :require_superadmin!
  # Admin::* 네임스페이스는 require_superadmin! 역할 게이트로 일괄 인가한다(per-action Pundit 아님).
  skip_after_action :verify_authorized

  private

  def require_superadmin!
    raise Pundit::NotAuthorizedError unless Current.user&.superadmin?
  end

  # 관리자 목록 공통 페이지네이션(#misc: admin 무페이지네이션). raw params[:page] 를
  # 잘라 [page, has_next?, records] 를 반환한다(전 카탈로그를 통짜 로드하지 않는다).
  # per_page 기본은 각 컨트롤러가 정의한 PER_PAGE.
  def paginate(scope, per_page: self.class::PER_PAGE)
    page = [ params[:page].to_i, 1 ].max
    records = scope.limit(per_page + 1).offset((page - 1) * per_page).to_a
    [ page, records.size > per_page, records.first(per_page) ]
  end
end
