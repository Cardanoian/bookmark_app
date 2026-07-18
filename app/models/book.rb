class Book < ApplicationRecord
  # 학년밴드 표준 라벨(게임 밴드 g12/g34/g56 과 정합). grade_band 는 표시·필터 전용이며
  # 게임 밴드(학생 학년에서 ReadingDomain.game_band_for 로 파생)와는 무관하다(계획 §3.1).
  GRADE_BANDS = [ "초등 1~2", "초등 3~4", "초등 5~6" ].freeze

  has_many :reports, dependent: :nullify
  has_many :book_recommendations, dependent: :destroy
  has_many :recommendation_imports, through: :book_recommendations

  enum :category, { recommended: 0, classic: 1, searched: 2 }, default: :recommended

  before_validation :normalize_isbn

  validates :title, presence: true
  # 모든 Book은 특정 판본의 유효한 ISBN-13을 식별자로 가진다. ISBN 없는 학생 자유입력은
  # Book 행을 만들지 않고 Report#book_title 폴백으로만 보존한다. 모델 검증은 폼/API를,
  # DB NOT NULL + 형식 CHECK + UNIQUE 인덱스는 우회·동시성 경로를 막는다.
  validates :isbn, presence: true, uniqueness: true
  validate :isbn_must_be_valid

  private

  def normalize_isbn
    return self.isbn = nil if isbn.blank?

    normalized = Books::Isbn.normalize(isbn)
    self.isbn = normalized if normalized
  end

  def isbn_must_be_valid
    return if isbn.blank? || Books::Isbn.normalize(isbn) == isbn

    errors.add(:isbn, "은 유효한 ISBN-10 또는 ISBN-13이어야 합니다")
  end
end
