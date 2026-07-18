class RecommendationImport < ApplicationRecord
  belongs_to :imported_by, class_name: "User", optional: true
  has_many :book_recommendations, dependent: :destroy
  has_many :books, through: :book_recommendations

  scope :active, -> { where(active: true) }

  validates :filename, :file_digest, :imported_at, presence: true
  validates :file_digest, uniqueness: true
  validates :item_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def self.current
    active.first
  end
end
