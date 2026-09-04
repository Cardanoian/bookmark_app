class ReportPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    return false unless user

    case user.role.to_sym
    when :superadmin
      true
    when :teacher
      teacher_of_classroom?
    when :student
      record.user_id == user.id
    when :school_admin, :librarian
      same_school?
    else
      false
    end
  end

  def create?
    user&.student?
  end

  def new?
    create?
  end

  def update?
    return false unless user

    record.user_id == user.id || teacher_of_classroom? || user.superadmin?
  end

  def edit?
    update?
  end

  # 목록 정리는 작성 학생 본인만 할 수 있다. 교사·관리자는 교육 기록을 대신 삭제하지 않는다.
  def destroy?
    user&.student? && record.user_id == user.id
  end

  # 고쳐쓰기는 작성자 본인만.
  def revise?
    user.present? && record.user_id == user.id
  end

  # 우수작 공유는 작성자 본인 또는 담당 교사(총괄 포함) + **담임 승인(reviewed) 후에만**.
  # 게시판은 학급을 넘어 열람되는 지면이라, 검토를 거치지 않은 글이 올라가면 되돌릴 수 없다
  # (approve? 가 record.submitted? 를 보는 것과 같은 이유의 상태 게이트다).
  #
  # `|| record.shared?` 는 **취소 경로를 열어 두기 위한 fail-safe** 다. 공유 중인 글이 어떤
  # 경위로든 미검토 상태가 되면(레거시 행·수동 조작) 공유를 걷을 방법이 없어 게시판에 박제된다.
  # ReportsController#submit_for_review 가 재제출 시 공유를 자동 해제하므로 정상 흐름에서는
  # 이 분기에 도달하지 않는다 — 핵심 방어가 아니라 마지막 안전장치다.
  def share?
    return false unless user
    return false unless record.user_id == user.id || teacher_of_classroom? || user.superadmin?

    record.reviewed? || record.shared?
  end

  # 검토·승인은 학급 담임(또는 superadmin)만.
  def review?
    return false unless user

    teacher_of_classroom? || user.superadmin?
  end

  # 승인은 **학생이 제출한 글**에만. 목록(`Teacher::ReviewsController#classroom_scope`)이 이미
  # 초안을 거르지만, 승인은 되돌릴 수 없는 확정(포인트·뱃지·진화·미션 캐스케이드)이라 URL 직접
  # 요청·batch_approve 의 id 배열 위조에 대해 정책에서도 fail-closed 로 막는다.
  def approve?
    review? && record.submitted?
  end

  private

  def teacher_of_classroom?
    user.teacher? && record.classroom&.teacher_id == user.id
  end

  def same_school?
    user.school_id.present? && record.classroom&.school_id == user.school_id
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user

      case user.role.to_sym
      when :superadmin
        scope.all
      when :teacher
        scope.where(classroom_id: Classroom.where(teacher_id: user.id).select(:id))
      when :student
        scope.where(user_id: user.id)
      when :school_admin, :librarian
        scope.joins(:classroom).where(classrooms: { school_id: user.school_id })
      else
        scope.none
      end
    end
  end
end
