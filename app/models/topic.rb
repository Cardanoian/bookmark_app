# 토론방(P5.4 + reading_discussion). classroom/school 스코프로 학급·학교 단위 토론을 구분하고,
# book 을 걸면 "그 책으로 나누는 독서 토론"이 된다(독서활동 화면 진입점이 book 으로 연결).
class Topic < ApplicationRecord
  # 토론 주제 길이(공백 포함). 저학년도 읽기 쉬운 짧은 제목을 유도한다.
  TITLE_LENGTH = 2..60

  enum :scope, { classroom: 0, school: 1 }, default: :classroom

  belongs_to :classroom, optional: true
  belongs_to :school, optional: true
  belongs_to :book, optional: true
  # 숨김 처리자(교사/총괄). 미숨김이면 nil.
  belongs_to :hidden_by, class_name: "User", optional: true
  has_many :forum_posts, dependent: :destroy

  validates :title, presence: true, length: { in: TITLE_LENGTH }
  validate :title_must_not_contain_denylisted_words
  # 스코프별 경계 컬럼을 강제한다. classroom 스코프인데 classroom_id 가 비면(교사 개설 시 담당
  # 학급 미선택 등) 아무에게도 안 보이는 고아 토픽이 된다 — 저장 시점에 막는다(정책 경계와 짝).
  validate :scope_boundary_present

  scope :visible, -> { where(hidden: false) }

  private

  def scope_boundary_present
    if classroom? && classroom_id.blank?
      errors.add(:classroom_id, "토론을 열 학급을 선택해 주세요.")
    elsif school? && school_id.blank?
      errors.add(:school_id, "학교 정보가 필요해요.")
    end
  end

  def title_must_not_contain_denylisted_words
    return if title.blank?

    hits = Moderation::TextDenylist.hits(title, list: Moderation::TextDenylist::FORUM)
    errors.add(:title, "에 쓸 수 없는 말이 있어요. 고운 말로 바꿔 주세요.") if hits.any?
  end
end
