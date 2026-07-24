# 책 소개 대결 글(교육 다양성 5종의 소셜 도메인). 학생이 도서별로 소개 글을 쓰고 또래가 투표한다.
# 경계=학급: 열람·투표는 BookIntroPolicy 가 같은 학급으로 강제한다(크로스-학급 차단).
class BookIntro < ApplicationRecord
  belongs_to :user
  belongs_to :book
  belongs_to :classroom

  has_many :book_intro_votes, dependent: :destroy

  validates :body, presence: true, length: { minimum: 10, maximum: 1000 }

  # 같은 도서·학급의 소개만(또래 경계). 득표순 → 최신순 랭킹.
  scope :for_classroom, ->(book, classroom) { where(book: book, classroom: classroom) }
  scope :ranked, -> { order(votes_count: :desc, created_at: :desc) }

  def voted_by?(user)
    return false unless user

    book_intro_votes.exists?(user_id: user.id)
  end
end
