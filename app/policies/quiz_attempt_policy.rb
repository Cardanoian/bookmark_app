# 퀴즈 플레이 기록 정책(P5.6). 플레이(생성)는 로그인 사용자, 열람은 본인 기록만.
class QuizAttemptPolicy < ApplicationPolicy
  def create?
    user.present?
  end

  def show?
    user.present? && record.user_id == user.id
  end
end
