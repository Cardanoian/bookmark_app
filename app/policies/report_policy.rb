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

  # 우수작 공유는 작성자 본인 또는 담당 교사(총괄 포함).
  def share?
    return false unless user

    record.user_id == user.id || teacher_of_classroom? || user.superadmin?
  end

  # 검토·승인·진위 확인은 학급 담임(또는 superadmin)만.
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

  def verify?
    review?
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
