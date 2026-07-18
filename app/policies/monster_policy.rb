# 몬스터 정책(P4.7). 도감 열람은 로그인 사용자, 진화·대표지정·먹이주기는 보유자 본인만.
class MonsterPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    user.present?
  end

  def choose_starter?
    user&.student?
  end

  def evolve?
    owns_record?
  end

  def set_active?
    owns_record?
  end

  private

  # record 는 current_user 스코프로 조회된 UserMonster(또는 미보유 시 nil).
  def owns_record?
    user.present? && record.respond_to?(:user_id) && record.user_id == user.id
  end
end
