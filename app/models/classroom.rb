class Classroom < ApplicationRecord
  belongs_to :school
  belongs_to :teacher, class_name: "User", optional: true
  has_many :users, dependent: :nullify

  validates :class_no, uniqueness: { scope: [ :school_id, :grade ] }

  def label
    "#{grade}학년 #{class_no}반"
  end
end
