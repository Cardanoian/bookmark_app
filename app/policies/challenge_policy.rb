# 챌린지 정책(P4.11). 열람은 로그인 사용자, 참여는 학생.
class ChallengePolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    user.present?
  end

  def join?
    user&.student?
  end
end
