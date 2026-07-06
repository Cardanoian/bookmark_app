# 토론 글 정책(P5.4). 토픽을 열람할 수 있는(경계 안) 사용자만 글 작성 가능.
class ForumPostPolicy < ApplicationPolicy
  def create?
    return false unless user

    TopicPolicy.new(user, record.topic).show?
  end
end
