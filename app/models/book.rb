class Book < ApplicationRecord
  has_many :reports, dependent: :nullify

  enum :category, { recommended: 0, classic: 1, searched: 2 }, default: :recommended

  validates :title, presence: true
end
