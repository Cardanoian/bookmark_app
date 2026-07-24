# 우수작 게시판 정책(P5.3). 숨김 글은 모더레이터(교사/교무/총괄)만 열람.
class BoardPostPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    return false unless user

    !record.hidden? || moderator?
  end

  private

  def moderator?
    user.teacher? || user.school_admin? || user.superadmin?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user

      moderator? ? scope.all : scope.visible
    end

    private

    def moderator?
      user.teacher? || user.school_admin? || user.superadmin?
    end
  end
end
