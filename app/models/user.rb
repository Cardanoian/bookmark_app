class User < ApplicationRecord
  include Pointable
  include Leveling
  include Evolvable
  include Badgeable

  has_secure_password

  belongs_to :school, optional: true
  belongs_to :classroom, optional: true
  belongs_to :active_monster, class_name: "UserMonster", optional: true

  has_many :reports, dependent: :destroy
  has_many :user_monsters, dependent: :destroy
  has_many :user_badges, dependent: :destroy
  has_many :badges, through: :user_badges
  has_many :purchases, dependent: :destroy
  has_many :forum_posts, dependent: :destroy
  has_many :cheers, dependent: :destroy
  has_many :quiz_attempts, dependent: :destroy

  enum :role, { student: 0, teacher: 1, school_admin: 2, librarian: 3, superadmin: 4 }, default: :student
  enum :mode, { normal: 0, easy: 1 }, default: :normal

  validates :name, presence: true
  validates :name, uniqueness: { scope: [ :school_id, :classroom_id ] }
  validates :password, length: { minimum: 6 }, allow_nil: true

  # 계정 생성·비밀번호 초기화 시 부여하는 랜덤 임시 비밀번호(0.5). 기본비번 "1234" 대체.
  # 최소 길이(6) 이상을 보장하며, 호출부에서 교사/관리자에게 노출해 학생에게 전달한다.
  def self.generate_temporary_password
    SecureRandom.alphanumeric(10)
  end
end
