# 뒷이야기 이어쓰기 글(게임 재구성 Phase 2의 창작 소셜 도메인). 책이 끝난 뒤 이어질 이야기를 학생이
# 창작하고 또래가 공감(👍)한다. 경계=학급: 열람·공감은 BookSequelPolicy 가 같은 학급으로 강제(크로스-학급 차단).
# 제출하면 SequelFeedbackJob 이 학생 글을 평가한 격려형 AI 코멘트를 비동기로 단다(ai_comment·ai_status).
class BookSequel < ApplicationRecord
  belongs_to :user
  belongs_to :book
  belongs_to :classroom

  has_many :book_sequel_votes, dependent: :destroy

  # 비동기 AI 격려 코멘트 상태(Report ai_status enum 미러). 무API 폴백이라 항상 done 에 도달한다.
  enum :ai_status, { pending: 0, processing: 1, done: 2, failed: 3 }, default: :pending

  # 이야기라 소개(intro, 10..1000)보다 길게 허용한다.
  validates :body, presence: true, length: { minimum: 10, maximum: 2000 }

  # 같은 도서·학급의 뒷이야기만(또래 경계). 득표순 → 최신순 랭킹.
  scope :for_classroom, ->(book, classroom) { where(book: book, classroom: classroom) }
  scope :ranked, -> { order(votes_count: :desc, created_at: :desc) }

  def voted_by?(user)
    return false unless user

    book_sequel_votes.exists?(user_id: user.id)
  end
end
