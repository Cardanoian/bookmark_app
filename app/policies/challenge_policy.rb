# 챌린지 정책(P4.11). 열람(show)은 Scope 와 대칭인 전국+소속학교 경계, 참여(join)는 학생, 관리(생성·수정·삭제)는 교직원.
# 관리 학교 경계: 총괄관리자=전권(전국·모든 학교), 교사·사서·교무=우리 학교의 '학교 스코프' 챌린지만.
# (scope·school_id 자체는 컨트롤러가 역할에서 파생해 위조를 차단하고, 정책은 레코드 단위 접근을 판정한다.)
class ChallengePolicy < ApplicationPolicy
  def index?
    user.present?
  end

  # 상세 열람 경계 = Scope 와 대칭(전국 + 소속 학교). show 진입 자체를 막아 타 학교 school 스코프
  # 챌린지 상세 조회 시 EvaluateProgress 가 크로스-스쿨 지연 참여·보상을 만드는 경로까지 함께 닫는다.
  def show?
    return false unless user
    return true if user.superadmin?

    record.global? || (user.school_id.present? && record.school_id == user.school_id)
  end

  def join?
    user&.student?
  end

  # 관리 콘솔 진입(목록의 '만들기' 노출 + new/create). 교직원(교사·사서·교무·총괄) 모두 허용.
  def manage?
    user&.staff?
  end

  def new?
    manage?
  end

  def create?
    manage?
  end

  def edit?
    manage_record?
  end

  def update?
    manage_record?
  end

  def destroy?
    manage_record?
  end

  # 목록·관리 대상 스코프: 총괄=전체, 그 외 로그인 사용자=전국 + 소속 학교.
  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none if user.blank?
      return scope.all if user.superadmin?

      scope.where(scope: :global).or(scope.where(scope: :school, school_id: user.school_id))
    end
  end

  private

  # 레코드 단위 관리(수정·삭제) 권한. 총괄=전권, 교사·사서·교무=우리 학교의 학교 스코프 챌린지만
  # (전국 챌린지·타 학교 챌린지는 총괄만 관리). global? 챌린지는 school_id 비교가 무의미하므로 명시적으로 배제.
  def manage_record?
    return false unless user&.staff?
    return true if user.superadmin?

    record.school? && record.school_id == user.school_id
  end
end
