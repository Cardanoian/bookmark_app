# 토론방 유형(2026-09-19). 개설할 때 "자유 의견"(free) / "찬반 토론"(debate)을 고른다.
# 찬반 토론은 글마다 입장(forum_posts.stance)을 받아 찬성·반대 칸으로 나눠 보여 준다.
# 기존 토론방은 모두 자유 의견(0)으로 남아 화면이 바뀌지 않는다.
class AddKindToTopics < ActiveRecord::Migration[8.1]
  def change
    add_column :topics, :kind, :integer, default: 0, null: false
  end
end
