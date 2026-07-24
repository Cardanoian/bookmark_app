# 독서 토론 아동 안전(reading_discussion PR). forum_posts 에 신고 카운터와 숨김 귀속을,
# topics 에 숨김 귀속을 additive 로 추가한다(board_posts.hidden_by_id 선례와 정합).
# 전량 additive·default 0 백필이라 기존 데이터 무손상.
class AddModerationToForumPosts < ActiveRecord::Migration[8.1]
  def change
    # 서로 다른 신고자 수(forum_post_reports counter_cache). 2인 자동숨김이 아니라
    # 교사 대시보드 사후 검토 신호로만 쓴다(또래 저작물 집단신고 괴롭힘 방지).
    add_column :forum_posts, :reports_count, :integer, default: 0, null: false

    # 숨김 처리자 귀속(교사/총괄). 모더레이션 컨트롤러의 respond_to?(:hidden_by_id) 분기와 정합.
    add_column :forum_posts, :hidden_by_id, :integer
    add_column :topics, :hidden_by_id, :integer
    add_index :forum_posts, :hidden_by_id
    add_index :topics, :hidden_by_id
  end
end
