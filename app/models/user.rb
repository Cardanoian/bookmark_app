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
  has_many :forum_posts, dependent: :destroy
  has_many :cheers, dependent: :destroy
  has_many :quiz_attempts, dependent: :destroy
  has_many :quiz_contributions, dependent: :destroy
  has_many :game_plays, dependent: :destroy
  has_many :mission_participations, dependent: :destroy
  has_many :audit_logs, foreign_key: :actor_id, dependent: :nullify, inverse_of: :actor
  has_many :recommendation_imports, foreign_key: :imported_by_id, dependent: :nullify,
                                    inverse_of: :imported_by

  enum :role, { student: 0, teacher: 1, school_admin: 2, librarian: 3, superadmin: 4 }, default: :student
  enum :mode, { normal: 0, easy: 1 }, default: :normal

  # 이메일은 저장 전 정규화(앞뒤 공백 제거 + 소문자화, 빈 값이면 NULL)한다. 이로써 DB 유니크
  # 인덱스만으로 대소문자 무관 유일성이 보장되고, 로그인 조회(sessions_controller#find_staff)도
  # 같은 규칙(소문자)으로 일치시킨다.
  before_validation :normalize_email
  before_validation :normalize_nickname

  validates :name, presence: true
  validates :name, uniqueness: { scope: [ :school_id, :classroom_id ] }
  validates :nickname, length: { in: 2..12 }, allow_nil: true
  validates :nickname,
            format: {
              with: /\A[가-힣A-Za-z0-9]+(?: [가-힣A-Za-z0-9]+)*\z/,
              message: "은 한글·영문·숫자와 단어 사이 공백만 사용할 수 있어요."
            },
            allow_nil: true
  validates :nickname, uniqueness: { scope: :school_id, case_sensitive: false }, allow_nil: true
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

  def ranking_profile_complete?
    !student? || nickname.present?
  end

  # 랭킹 표면은 실명으로 폴백하지 않는다. 레거시·경합으로 닉네임이 비어도 익명 라벨만 노출한다.
  def ranking_name
    nickname.presence || "익명 학생"
  end

  private

  # 이메일 정규화: 앞뒤 공백 제거 + 소문자화, 빈 문자열은 NULL 로 저장(유니크 인덱스 NULL 다중 허용).
  def normalize_email
    self.email = email.to_s.strip.downcase.presence
  end

  def normalize_nickname
    self.nickname = nickname.to_s.squish.presence
  end
end
