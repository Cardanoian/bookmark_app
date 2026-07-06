# 토론 글(P5.4). likes_count 는 좋아요 카운터. hidden 은 모더레이션용.
class CreateForumPosts < ActiveRecord::Migration[8.1]
  def change
    create_table :forum_posts do |t|
      t.references :topic, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :text
      t.integer :likes_count, null: false, default: 0
      t.boolean :hidden, null: false, default: false

      t.timestamps
    end
  end
end
