# 사서 도구 공통 베이스(P6.5). 사서(또는 총괄)만 접근 가능하며, 모든 조회·수정은
# 자기 학교로 스코프한다(경계). 타역할·타학교 → 403.
class Librarian::BaseController < ApplicationController
  before_action :require_librarian!
  # Librarian::* 네임스페이스는 require_librarian! 역할 게이트로 일괄 인가한다(per-action Pundit 아님).
  skip_after_action :verify_authorized

  private

  def require_librarian!
    raise Pundit::NotAuthorizedError unless Current.user&.librarian? || Current.user&.superadmin?
  end

  # 사서의 소속 학교(경계 스코프). 총괄은 school_id 파라미터로 학교를 선택할 수 있다.
  def current_school
    @current_school ||=
      if Current.user.superadmin?
        School.find_by(id: params[:school_id]) || Current.user.school
      else
        Current.user.school
      end
  end
end
