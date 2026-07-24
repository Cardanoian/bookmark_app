# 책 소개 대결(book, 교육 다양성 5종 중 소셜 도메인). 학생이 도서별로 소개 글을 쓰고 또래가
# 투표한다. 경계는 학급(classroom) — 정책이 같은 학급 소개만 열람·투표하게 강제한다.
# votes_count 는 BookIntroVote counter_cache(득표순 랭킹).
class CreateBookIntros < ActiveRecord::Migration[8.1]
  def change
    create_table :book_intros do |t|
      t.references :user, null: false, foreign_key: true
      t.references :book, null: false, foreign_key: true
      t.references :classroom, null: false, foreign_key: true
      t.text :body, null: false
      t.integer :votes_count, null: false, default: 0

      t.timestamps
    end

    add_index :book_intros, [ :book_id, :classroom_id ]
  end
end
