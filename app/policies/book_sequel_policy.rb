# 뒷이야기 이어쓰기 정책. 경계=학급: 뒷이야기 열람·공감은 같은 학급 학생만(크로스-학급 차단).
# 작성은 학급 소속 학생, 공감은 같은 학급 또래의 글만(자기 글 공감 불가), 회수는 본인 학급 내.
class BookSequelPolicy < ApplicationPolicy
  def create?
    user&.student? && user.classroom_id.present?
  end

  # 같은 학급 또래의 뒷이야기에만 공감(자기 글은 제외 — 공정성).
  def vote?
    same_classroom_student? && record.user_id != user.id
  end

  # 자기 공감 회수는 같은 학급 학생이면 허용.
  def unvote?
    same_classroom_student?
  end

  private

  def same_classroom_student?
    return false unless user&.student?

    record.classroom_id.present? && record.classroom_id == user.classroom_id
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user&.classroom_id

      scope.where(classroom_id: user.classroom_id)
    end
  end
end
