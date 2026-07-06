# 단계 학습 위저드 정책(P5.5). 로그인 사용자면 진행 가능(trivial).
class LearnPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def advance?
    index?
  end
end
