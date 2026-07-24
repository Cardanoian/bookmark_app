# 몬스터 발견 연출 확인(acknowledge). 축하 모달을 본 학생이 호출해 미연출 개체의
# celebrated_at 을 마킹하고 재노출을 막는다(영속 드레인 — flash·Action Cable 이 닿지 못한
# 오프라인/교사 트리거 발견도 다음 로드에서 확인). 실제 발견·지급은 MonsterUnlock 이 담당하며
# 여기서는 연출 완료 표시만 한다.
class DiscoveriesController < ApplicationController
  before_action :require_student

  # 상태 마킹 전용 액션이라 Pundit authorize 를 호출하지 않는다(학생 게이트로 충분).
  skip_after_action :verify_authorized

  # 학생 본인의 미연출(celebrated_at IS NULL) 몬스터를 연출 완료로 마킹한다.
  # dex_no[] 파라미터가 오면 그 라인만, 없으면 전부. update_all 로 콜백 없이 일괄 처리하며
  # 부분 인덱스(celebrated_at IS NULL)로 경량이다.
  def acknowledge
    scope = current_user.user_monsters.pending_celebration
    dex_nos = Array(params[:dex_no]).map(&:to_i).reject(&:zero?)
    scope = scope.where(dex_no: dex_nos) if dex_nos.any?
    scope.update_all(celebrated_at: Time.current)

    head :ok
  end

  private

  # 도감은 학생 전용 개념이라 학생만 연출/확인한다(비학생은 애초에 미연출 개체가 없다).
  def require_student
    head :forbidden unless current_user&.student?
  end
end
