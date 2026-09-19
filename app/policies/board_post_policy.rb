# 우수작 게시판 정책(P5.3). 게시물은 글이 쓰인 학급의 학교 안에서만 보인다(총괄관리자만 전체).
# 게시판은 실명과 독후감 전문을 보여 주므로, 여러 학교가 한 서버를 쓸 때 다른 학교로 넘어가지 않게 한다.
# 숨김 글은 같은 학교의 모더레이터(교사/교무)와 총괄만 열람.
class BoardPostPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    return false unless user
    return true if user.superadmin?
    return false unless same_school?

    !record.hidden? || moderator?
  end

  private

  def moderator?
    user.teacher? || user.school_admin?
  end

  def same_school?
    user.school_id.present? && record.report&.classroom&.school_id == user.school_id
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user
      return scope.all if user.superadmin?
      return scope.none if user.school_id.blank?

      same_school = scope.joins(report: :classroom).where(classrooms: { school_id: user.school_id })
      moderator? ? same_school : same_school.visible
    end

    private

    def moderator?
      user.teacher? || user.school_admin?
    end
  end
end
