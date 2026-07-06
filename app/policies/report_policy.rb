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

  def approve?
    review?
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
