class ClassroomPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    return false unless user

    case user.role.to_sym
    when :superadmin
      true
    when :teacher
      record.teacher_id == user.id
    when :student
      record.id == user.classroom_id
    when :school_admin, :librarian
      record.school_id == user.school_id
    else
      false
    end
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user

      case user.role.to_sym
      when :superadmin
        scope.all
      when :teacher
        scope.where(teacher_id: user.id)
      when :student
        scope.where(id: user.classroom_id)
      when :school_admin, :librarian
        scope.where(school_id: user.school_id)
      else
        scope.none
      end
    end
  end
end
