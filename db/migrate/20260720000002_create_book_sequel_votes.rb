# 뒷이야기 공감(👍). 뒷이야기당 1인 1표(cheer 패턴) — (book_sequel, user) 조합 unique.
# book_sequel.votes_count 를 counter_cache 로 증감한다(득표순 랭킹).
class CreateBookSequelVotes < ActiveRecord::Migration[8.1]
  def change
    create_table :book_sequel_votes do |t|
      t.references :book_sequel, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end

    add_index :book_sequel_votes, [ :book_sequel_id, :user_id ], unique: true
  end
end
