# 게시판 글 좋아요 정책(P5.4). 토픽을 열람 가능한(경계 안) 사용자만 좋아요, 취소는 본인 좋아요만.
class ForumPostLikePolicy < ApplicationPolicy
  def create?
    return false unless user

    TopicPolicy.new(user, record.forum_post.topic).show?
  end

  def destroy?
    return false unless user

    record.user_id == user.id
  end
end
