# 책 소개 대결 정책. 경계=학급: 소개 열람·투표는 같은 학급 학생만(크로스-학급 차단).
# 작성은 학급 소속 학생, 투표는 같은 학급 또래의 소개만(자기 소개 투표 불가), 회수는 본인 학급 내.
class BookIntroPolicy < ApplicationPolicy
  def create?
    user&.student? && user.classroom_id.present?
  end

  # 같은 학급 또래의 소개에만 투표(자기 소개는 제외 — 대결 공정성).
  def vote?
    same_classroom_student? && record.user_id != user.id
  end

  # 자기 표 회수는 같은 학급 학생이면 허용.
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
