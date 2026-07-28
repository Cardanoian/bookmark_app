class User < ApplicationRecord
  include Pointable
  include Leveling
  include Evolvable
  include Badgeable

  has_secure_password

  belongs_to :school, optional: true
  belongs_to :classroom, optional: true
  belongs_to :active_monster, class_name: "UserMonster", optional: true
  belongs_to :ai_consent_recorded_by, class_name: "User", optional: true

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
  has_many :challenge_participations, dependent: :destroy
  has_many :audit_logs, foreign_key: :actor_id, dependent: :nullify, inverse_of: :actor
  has_many :recommendation_imports, foreign_key: :imported_by_id, dependent: :nullify,
                                    inverse_of: :imported_by

  enum :role, { student: 0, teacher: 1, school_admin: 2, librarian: 3, superadmin: 4 }, default: :student

  # 비밀번호 재설정 링크 유효시간. 메일 문안의 "15분"은 이 상수에서 파생되므로(AccountMailer 가
  # `@expires_in_text` 로 주입) 값을 바꾸면 문안도 자동으로 따라온다(문서-코드 드리프트 차단).
  PASSWORD_RESET_EXPIRY = 15.minutes
  # 가입 인증 링크 유효시간.
  EMAIL_VERIFICATION_EXPIRY = 24.hours
  # 가입 후 인증 게이트가 유예되는 시간. 메일 지연·스팸함 유입·발송 실패가 실제로 발생하고,
  # 가입 직후가 담임이 학생 계정을 만드는 시점이라 유예 없이 즉시 제한하면 **정상 교사가 첫
  # 사용에서 막히는 확률**이 미인증 악용 확률보다 높다.
  EMAIL_VERIFICATION_GRACE = 24.hours

  # 비밀번호 재설정 토큰. `password_salt`(bcrypt 다이제스트의 salt 부분)에 바인딩해 **비밀번호가
  # 바뀌면 이전에 발급된 모든 토큰이 즉시 무효**가 된다 — 재설정 성공이 곧 그 토큰의 소비이므로
  # DB 컬럼 없이 1회용에 준하는 성질을 얻는다(Rails 8 인증 제너레이터와 동일한 관용구).
  # salt 조각은 비밀이 아니라 "비번이 바뀌었는지"를 판별하는 지문이고, 토큰 자체의 위조 방지는
  # secret_key_base 서명이 담당한다.
  generates_token_for :password_reset, expires_in: PASSWORD_RESET_EXPIRY do
    password_salt&.last(10)
  end

  # 가입 이메일 인증 토큰. 이메일에 바인딩해 **주소가 바뀌면 이전 토큰이 무효**가 된다(오타를
  # 고친 뒤 옛 주소로 온 링크가 새 주소를 인증해 버리는 일을 막는다).
  generates_token_for :email_verification, expires_in: EMAIL_VERIFICATION_EXPIRY do
    email
  end

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

  # 이메일 비밀번호 재설정 대상 판정(**fail-closed**). 학생은 이메일 로그인 대상이 아니고
  # (튜플 로그인) 담임이 `Teacher::StudentsController#reset_password` 로 직접 초기화하므로,
  # 학생 계정에 어쩌다 이메일이 들어 있어도 이 경로로는 절대 재설정되지 않아야 한다.
  # 정지 계정도 제외한다 — 어차피 로그인이 막히므로 재설정 메일을 보낼 이유가 없다.
  def password_reset_eligible?
    staff? && email.present? && !suspended?
  end

  def email_verified?
    email_verified_at.present?
  end

  # 미인증 배너 노출 조건. 공개 가입 경로는 교사뿐이지만(RegistrationsController), 총괄이 만든
  # 교직원 계정도 미인증이면 배너로 안내하고 재발송할 수 있게 한다(staff? 로 넓게 잡는다).
  def email_verification_pending?
    staff? && email.present? && !email_verified?
  end

  # 인증 게이트 발동 조건(**fail-open** — 셋을 모두 만족할 때만 잠긴다).
  #   ① 메일 발송이 실제로 가능한 환경일 것 — 무키 개발·CI·오프라인 시연에서는 게이트가 통째로
  #      꺼져 기존 흐름이 100% 보존되고, 운영 중 메일 장애가 길어지면 운영자가 credentials 에서
  #      키를 비워 게이트를 즉시 전면 해제할 수 있다(비상 킬 스위치).
  #   ② 교사이고 미인증일 것 — 게이트가 막는 것은 '학생 계정을 만들고 조작하는 행위'뿐이고,
  #      그 권한을 가진 역할은 교사다.
  #   ③ 가입 유예(EMAIL_VERIFICATION_GRACE)가 지났을 것.
  #
  # 게이트의 목적은 침입자 차단이 아니라 **복구 가능성 보장**이다. 이메일이 오타·가짜면 그 교사는
  # 비밀번호 재설정을 영원히 할 수 없는데(교직원에겐 대신 초기화해 줄 담임이 없다), 인증에 아무
  # 결과가 따르지 않으면 인증률이 0에 수렴해 재설정 기능 자체가 무의미해진다. 남의 계정을 책임지기
  # 시작하는 시점이 곧 자기 계정 복구 수단부터 확보해야 하는 시점이라, 제한 대상을 거기에 맞췄다.
  def email_verification_gate_active?
    return false unless Mail::ResendGateway.available?
    return false unless teacher? && email_verification_pending?

    created_at.present? && created_at <= EMAIL_VERIFICATION_GRACE.ago
  end

  # AI 활용 동의(P1-1, fail-closed). §1 개인정보 필수동의(privacy_consent_at)와 §2 AI 동의(ai_consent)가
  # 모두 있어야 학생 데이터를 외부 AI(Claude)로 보낸다. 비학생·미기록은 false → 규칙기반 폴백.
  # `Ai::ConsentGate.llm_allowed?` 가 이 술어로 첨삭·진위·뒷이야기·OCR 경로를 게이팅한다.
  def ai_consented?
    student? && ai_consent? && privacy_consent_at.present?
  end

  def ranking_profile_complete?
    !student? || nickname.present?
  end

  # 랭킹 개인 표시는 공개에 동의한 학생의 닉네임만 쓴다. 비공개 학생도 성취 집계에는 포함하되,
  # 이름·닉네임·대표 몬스터를 연결할 수 없도록 이 술어와 ranking_name 을 함께 사용한다.
  def ranking_identity_visible?
    student? && ranking_opted_in?
  end

  # 랭킹 표면은 실명으로 폴백하지 않는다. 공개에 동의하지 않았거나 레거시·경합으로 닉네임이
  # 비어도 비식별 라벨만 노출한다.
  def ranking_name
    return nickname if ranking_identity_visible? && nickname.present?

    "비공개 학생"
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
