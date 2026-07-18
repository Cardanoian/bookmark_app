# 토론방 정책(P5.4 + reading_discussion). 경계 격리는 역할별로 다르다:
#   학생 — 자기 학급(classroom_id) 스코프 + 자기 학교(school_id) 스코프.
#   교사 — 담당 학급(Classroom.teacher_id == user.id) 스코프 + 자기 학교 스코프.
#          교사는 user.classroom_id 가 nil 이라 학생과 같은 규칙을 쓰면 자기 학급 토픽을 못 본다.
#   총괄 — 전체.
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
      return false if record.classroom_id.blank?

      user.teacher? ? teaches_classroom?(record.classroom_id) : record.classroom_id == user.classroom_id
    elsif record.school?
      record.school_id.present? && record.school_id == user.school_id
    else
      false
    end
  end

  # 교사가 이 학급의 담임(다학급 가능)인지. 교사↔학급의 단일 진실은 Classroom.teacher_id.
  def teaches_classroom?(classroom_id)
    Classroom.where(id: classroom_id, teacher_id: user.id).exists?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user
      return scope.all if user.superadmin?

      visible = scope.visible
      classroom_ids = user.teacher? ? Classroom.where(teacher_id: user.id).select(:id) : user.classroom_id
      visible.where(scope: :classroom, classroom_id: classroom_ids)
             .or(visible.where(scope: :school, school_id: user.school_id))
    end
  end
end
