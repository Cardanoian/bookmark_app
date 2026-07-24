class BookRecommendation < ApplicationRecord
  belongs_to :recommendation_import
  belongs_to :book

  validates :section, presence: true
  validates :position, numericality: { only_integer: true, greater_than: 0 }
  validates :book_id, uniqueness: { scope: :recommendation_import_id }
end
