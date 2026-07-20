# 뒷이야기 공감(👍). 뒷이야기당 1인 1표(cheer 패턴). votes_count 는 counter_cache 로 자동 증감한다.
class BookSequelVote < ApplicationRecord
  belongs_to :book_sequel, counter_cache: :votes_count
  belongs_to :user

  validates :user_id, uniqueness: { scope: :book_sequel_id }
end
