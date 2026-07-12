# 책 소개 투표(👍). 소개당 1인 1표(cheer 패턴) — (book_intro, user) 조합 unique.
# book_intro.votes_count 를 counter_cache 로 증감한다.
class CreateBookIntroVotes < ActiveRecord::Migration[8.1]
  def change
    create_table :book_intro_votes do |t|
      t.references :book_intro, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end

    add_index :book_intro_votes, [ :book_intro_id, :user_id ], unique: true
  end
end
