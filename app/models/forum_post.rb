# 토론 글(P5.4 + reading_discussion 아동 안전). 좋아요는 forum_post_likes(1인 1좋아요)로
# counter_cache(likes_count), 신고는 forum_post_reports(1인 1신고)로 counter_cache(reports_count).
class ForumPost < ApplicationRecord
  # 저학년 자유입력 안전 상한(공백 포함). 너무 짧은 도배·과도한 장문을 막는다.
  TEXT_LENGTH = 2..500

  # 찬반 토론 글의 입장. 자유 의견 토론방의 글은 nil. 없는 값(조작한 stance=bogus)은 검증 오류가 된다.
  enum :stance, { pro: 0, con: 1 }, validate: { allow_nil: true }

  STANCE_LABELS = { "pro" => "찬성", "con" => "반대" }.freeze

  belongs_to :topic, counter_cache: true
  belongs_to :user
  # 숨김 처리자(교사/총괄). 미숨김이면 nil.
  belongs_to :hidden_by, class_name: "User", optional: true

  has_many :forum_post_likes, dependent: :destroy
  has_many :forum_post_reports, dependent: :destroy

  validates :text, presence: true, length: { in: TEXT_LENGTH }
  # 명백한 욕설만 저장 거부(FORUM 리스트 — 오탐 위험 낱말 제외). 잔여는 신고·모더레이션으로 회수.
  validate :text_must_not_contain_denylisted_words
  # 글을 만들 때와 입장을 바꿀 때만 본다 — 숨김·해제(update!)는 입장과 무관하므로, 방식과 어긋난
  # 옛 글(예: 콘솔에서 찬반 토론으로 바꾼 토론방의 입장 없는 글)도 모더레이션이 막히지 않게.
  validate :stance_must_match_topic_kind, if: -> { new_record? || will_save_change_to_stance? }

  scope :visible, -> { where(hidden: false) }

  # 사용자가 이 글을 좋아요했는지 여부.
  def liked_by?(user)
    user && forum_post_likes.exists?(user_id: user.id)
  end

  # 사용자가 이 글을 신고했는지 여부.
  def reported_by?(user)
    user && forum_post_reports.exists?(user_id: user.id)
  end

  private

  # 찬반 토론은 입장을 꼭 고르고, 자유 의견에는 입장을 두지 않는다(폼에 없는 값을 조작해 보낸 경우).
  def stance_must_match_topic_kind
    if topic&.debate?
      errors.add(:base, "찬성인지 반대인지 골라 주세요.") if stance.nil?
    elsif !stance.nil?
      errors.add(:base, "자유 의견 토론방에서는 찬성·반대를 고르지 않아요.")
    end
  end

  def text_must_not_contain_denylisted_words
    return if text.blank?

    hits = Moderation::TextDenylist.hits(text, list: Moderation::TextDenylist::FORUM)
    errors.add(:text, "에 쓸 수 없는 말이 있어요. 고운 말로 바꿔 주세요.") if hits.any?
  end
end
