# 토론 글 신고 원장(reading_discussion 아동 안전). 글당 **1인 1신고**(quiz_report 패턴 복제,
# (forum_post, user) unique). forum_post.reports_count 를 counter_cache 로 증감해 "서로 다른
# 신고자 수"를 센다. **자동 숨김은 하지 않는다**(또래 저작물 집단신고 괴롭힘 벡터 차단) —
# 접수는 저자 학급 담임 대시보드 "신고된 토론 글" 섹션의 사후 검토 신호로만 쓰이고, 실제 숨김은
# 담임(Teacher::ForumModerations)·총괄(Admin::Moderation)의 수동 판단으로만 이뤄진다.
class ForumPostReport < ApplicationRecord
  belongs_to :forum_post, counter_cache: :reports_count
  belongs_to :user

  validates :user_id, uniqueness: { scope: :forum_post_id }
end
