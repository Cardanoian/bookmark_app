class School < ApplicationRecord
  has_many :classrooms, dependent: :destroy
  has_many :users, dependent: :nullify

  validates :name, presence: true
  validates :neis_code, uniqueness: true, allow_nil: true
end
