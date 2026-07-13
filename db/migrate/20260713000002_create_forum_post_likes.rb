# 게시판 글 좋아요(👍). forum_post + user 조합은 1인 1좋아요(unique), likes_count counter_cache.
class CreateForumPostLikes < ActiveRecord::Migration[8.1]
  def change
    create_table :forum_post_likes do |t|
      t.references :forum_post, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end

    add_index :forum_post_likes, [ :forum_post_id, :user_id ], unique: true
  end
end
