# 토론 글 신고 정책(reading_discussion). 대상 토픽을 열람 가능(TopicPolicy#show?)한 사용자만
# 신고할 수 있고(경계 밖 차단), **자기 글은 신고할 수 없다**(무의미·악용 방지). record 는
# 아직 저장 전 ForumPostReport(forum_post 연결됨).
class ForumPostReportPolicy < ApplicationPolicy
  def create?
    return false unless user
    return false if record.forum_post.user_id == user.id

    TopicPolicy.new(user, record.forum_post.topic).show?
  end
end
