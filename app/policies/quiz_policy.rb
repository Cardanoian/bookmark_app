# 퀴즈 정책(P5.6). 게시된(published) 퀴즈는 로그인 학생/교사가 열람·플레이 가능,
# 생성·수정은 교사/총괄만(전체 교사 CRUD UI 는 Phase 6). 총괄은 전권.
class QuizPolicy < ApplicationPolicy
  def show?
    return false unless user

    record.published? || manage?
  end

  def create?
    manage?
  end

  def update?
    manage?
  end

  def new?
    create?
  end

  def edit?
    update?
  end

  private

  def manage?
    user&.teacher? || user&.superadmin?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user
      return scope.all if user.teacher? || user.superadmin?

      scope.published
    end
  end
end
