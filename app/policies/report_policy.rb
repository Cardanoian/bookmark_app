class ReportPolicy < ApplicationPolicy
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

  def update?
    return false unless user

    record.user_id == user.id || teacher_of_classroom? || user.superadmin?
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
