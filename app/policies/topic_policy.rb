# 토론방 정책(P5.4). 학생/교사는 자기 학급-스코프 + 자기 학교-스코프 토픽만 열람.
# 다른 학급/학교 경계 밖 토픽은 차단된다.
class TopicPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    return false unless user
    return true if user.superadmin?

    within_boundary?
  end

  def create?
    user.present? && (user.student? || user.teacher?)
  end

  private

  def within_boundary?
    return false if record.hidden?

    if record.classroom?
      record.classroom_id.present? && record.classroom_id == user.classroom_id
    elsif record.school?
      record.school_id.present? && record.school_id == user.school_id
    else
      false
    end
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user
      return scope.all if user.superadmin?

      visible = scope.visible
      visible.where(scope: :classroom, classroom_id: user.classroom_id)
             .or(visible.where(scope: :school, school_id: user.school_id))
    end
  end
end
