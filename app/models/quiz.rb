# 독서 퀴즈(P5.6). 교사/총괄이 출제하고 published 플래그로 학생 노출을 통제한다.
# scope classroom(학급 한정) / global(전역). 문항은 position 순서로 재생된다.
class Quiz < ApplicationRecord
  belongs_to :created_by, class_name: "User"
  belongs_to :book, optional: true
  belongs_to :classroom, optional: true

  has_many :quiz_questions, -> { order(:position) }, dependent: :destroy, inverse_of: :quiz
  has_many :quiz_attempts, dependent: :destroy

  accepts_nested_attributes_for :quiz_questions, allow_destroy: true

  enum :scope, { classroom: 0, global: 1 }

  validates :title, presence: true

  scope :published, -> { where(published: true) }
end
