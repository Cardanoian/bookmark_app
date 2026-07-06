class User < ApplicationRecord
  has_secure_password

  belongs_to :school, optional: true
  belongs_to :classroom, optional: true

  has_many :reports, dependent: :destroy

  enum :role, { student: 0, teacher: 1, school_admin: 2, librarian: 3, superadmin: 4 }, default: :student
  enum :mode, { normal: 0, easy: 1 }, default: :normal

  validates :name, presence: true
  validates :name, uniqueness: { scope: [ :school_id, :classroom_id ] }
end
