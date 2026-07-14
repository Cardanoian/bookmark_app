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

  # 이메일은 저장 전 정규화(앞뒤 공백 제거 + 소문자화, 빈 값이면 NULL)한다. 이로써 DB 유니크
  # 인덱스만으로 대소문자 무관 유일성이 보장되고, 로그인 조회(sessions_controller#find_staff)도
  # 같은 규칙(소문자)으로 일치시킨다.
  before_validation :normalize_email

  validates :name, presence: true
  validates :name, uniqueness: { scope: [ :school_id, :classroom_id ] }
  validates :password, length: { minimum: 6 }, allow_nil: true
  # 교직원(교사·관리자·사서)은 이메일로 로그인하고 학생은 튜플로 로그인한다. 그래서 이메일은
  # 학생에겐 없어도 되고 교직원에겐 로그인 식별자다. 여기선 presence 를 강제하지 않고(이메일
  # 없는 계정 생성 자체는 허용 — 로그인만 불가), 형식·유일성만 검증한다. 실제 로그인 흐름이
  # "이메일 없으면 교직원 로그인 불가"를 강제하고, 교사 가입(registrations)에서 이메일을 필수로 받는다.
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :email, uniqueness: { case_sensitive: false }, allow_blank: true

  # 학생을 제외한 역할(교사·교무관리자·사서·총괄관리자) = 이메일 로그인 대상.
  def staff?
    !student?
  end

  # 계정 생성·비밀번호 초기화 시 부여하는 랜덤 임시 비밀번호(0.5). 기본비번 "1234" 대체.
  # 최소 길이(6) 이상을 보장하며, 호출부에서 교사/관리자에게 노출해 학생에게 전달한다.
  def self.generate_temporary_password
    SecureRandom.alphanumeric(10)
  end

  private

  # 이메일 정규화: 앞뒤 공백 제거 + 소문자화, 빈 문자열은 NULL 로 저장(유니크 인덱스 NULL 다중 허용).
  def normalize_email
    self.email = email.to_s.strip.downcase.presence
  end
end
