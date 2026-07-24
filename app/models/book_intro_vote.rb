# 책 소개 투표(👍). 소개당 1인 1표(cheer 패턴). votes_count 는 counter_cache 로 자동 증감한다.
class BookIntroVote < ApplicationRecord
  belongs_to :book_intro, counter_cache: :votes_count
  belongs_to :user

  validates :user_id, uniqueness: { scope: :book_intro_id }
end
