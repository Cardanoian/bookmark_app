class Book < ApplicationRecord
  # 학년밴드 표준 라벨(게임 밴드 g12/g34/g56 과 정합). grade_band 는 표시·필터 전용이며
  # 게임 밴드(학생 학년에서 ReadingDomain.game_band_for 로 파생)와는 무관하다(계획 §3.1).
  GRADE_BANDS = [ "초등 1~2", "초등 3~4", "초등 5~6" ].freeze

  has_many :reports, dependent: :nullify
  has_many :book_recommendations, dependent: :destroy
  has_many :recommendation_imports, through: :book_recommendations

  enum :category, { recommended: 0, classic: 1, searched: 2 }, default: :recommended

  before_validation :normalize_isbn
  before_validation :upgrade_cover_url_to_https

  validates :title, presence: true
  # 모든 Book은 특정 판본의 유효한 ISBN-13을 식별자로 가진다. ISBN 없는 학생 자유입력은
  # Book 행을 만들지 않고 Report#book_title 폴백으로만 보존한다. 모델 검증은 폼/API를,
  # DB NOT NULL + 형식 CHECK + UNIQUE 인덱스는 우회·동시성 경로를 막는다.
  validates :isbn, presence: true, uniqueness: true
  validate :isbn_must_be_valid

  private

  def normalize_isbn
    return self.isbn = nil if isbn.blank?

    normalized = Books::Isbn.normalize(isbn)
    self.isbn = normalized if normalized
  end

  # 표지 URL 은 페이지의 이미지 하위리소스라, HTTPS 배포(force_ssl)에서 http:// 로 저장되면
  # 브라우저가 혼합 콘텐츠(Mixed Content)로 차단해 표지가 뜨지 않는다. 알라딘·네이버 등 표지
  # 호스트는 모두 https 를 지원하므로, 저장 전 선행 http:// 를 https:// 로 승격해 이 사고를
  # 원천 차단한다(멱등 — 이미 https 이거나 blank 면 무변경). 시드·검색·보강·관리자 입력 등
  # 모든 쓰기 경로가 이 콜백을 경유한다.
  def upgrade_cover_url_to_https
    return if cover_url.blank?

    self.cover_url = cover_url.sub(%r{\Ahttp://}i, "https://")
  end

  def isbn_must_be_valid
    return if isbn.blank? || Books::Isbn.normalize(isbn) == isbn

    errors.add(:isbn, "은 유효한 ISBN-10 또는 ISBN-13이어야 합니다")
  end
end
