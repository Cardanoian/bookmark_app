# 찬반 토론 글의 입장(2026-09-19). pro(0)=찬성, con(1)=반대.
# 자유 의견 토론방의 글과 기존 글은 입장이 없으므로 null 을 허용한다(유형 일치는 모델 검증이 맡는다).
class AddStanceToForumPosts < ActiveRecord::Migration[8.1]
  def change
    add_column :forum_posts, :stance, :integer
  end
end
