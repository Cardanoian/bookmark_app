# 뒷이야기 이어쓰기 글(게임 재구성 Phase 2의 창작 소셜 도메인). 책이 끝난 뒤 이어질 이야기를 학생이
# 창작하고 또래가 공감(👍)한다. 경계=학급: 열람·공감은 BookSequelPolicy 가 같은 학급으로 강제(크로스-학급 차단).
# 제출하면 SequelFeedbackJob 이 학생 글을 평가한 격려형 AI 코멘트를 비동기로 단다(ai_comment·ai_status).
# 그 코멘트는 **담임이 승인해야** 작성 학생에게 보인다(comment_visible?, 2026-09-19 — 독후감 첨삭의
# feedback_visible? 와 같은 규칙). 담임은 승인 전에 코멘트를 고칠 수 있고, 고친 글은 teacher_comment 에
# 따로 두어 AI 원문(ai_comment)을 보존한다.
class BookSequel < ApplicationRecord
  belongs_to :user
  belongs_to :book
  belongs_to :classroom
  belongs_to :reviewed_by, class_name: "User", optional: true

  has_many :book_sequel_votes, dependent: :destroy

  # 담임이 적는 코멘트 상한. 학생 글(2000자)에 다는 짧은 격려라 절반이면 넉넉하다.
  COMMENT_MAX_LENGTH = 1000

  # 비동기 AI 격려 코멘트 상태(Report ai_status enum 미러). 무API 폴백이라 항상 done 에 도달한다.
  enum :ai_status, { pending: 0, processing: 1, done: 2, failed: 3 }, default: :pending

  # 이야기라 소개(intro, 10..1000)보다 길게 허용한다.
  validates :body, presence: true, length: { minimum: 10, maximum: 2000 }

  # 같은 도서·학급의 뒷이야기만(또래 경계). 득표순 → 최신순 랭킹.
  scope :for_classroom, ->(book, classroom) { where(book: book, classroom: classroom) }
  scope :ranked, -> { order(votes_count: :desc, created_at: :desc) }
  # 담임 검토를 기다리는 글 — 코멘트 잡이 끝났고(done·failed) 아직 승인하지 않았다. 잡이 도는 중인 글은
  # 뺀다(승인과 잡이 겹치면 담임이 읽지 않은 코멘트가 학생에게 간다). 반대 방향 — 승인한 글에 잡이 다시
  # 도는 경우 — 은 SequelFeedbackJob 의 조건부 전이가 막는다.
  scope :awaiting_review, -> { where(reviewed_at: nil, ai_status: %i[done failed]) }
  scope :reviewed, -> { where.not(reviewed_at: nil) }

  def voted_by?(user)
    return false unless user

    book_sequel_votes.exists?(user_id: user.id)
  end

  def reviewed?
    reviewed_at.present?
  end

  # 코멘트 잡이 끝나 담임이 승인할 수 있는 상태인가.
  def reviewable?
    done? || failed?
  end

  # 학생에게 보일 코멘트 — 담임이 고친 글이 있으면 그것, 없으면 AI 원문.
  def final_comment
    teacher_comment.presence || ai_comment.presence
  end

  # 단일 학생 노출 게이트. 뷰·방송은 이 술어 하나만 본다(조건 분산 금지).
  def comment_visible?
    reviewed? && final_comment.present?
  end

  # 담임 승인(또는 승인 뒤 다시 고치기). comment 는 폼에 적힌 최종 코멘트로, AI 원문과 같으면
  # teacher_comment 를 비워 "고치지 않고 승인"을 그대로 남긴다. 처음 승인한 교사·시각은 다시 고쳐도
  # 바꾸지 않는다. 빈 코멘트는 승인하지 않는다(AI 가 코멘트를 못 만든 글은 담임이 직접 적는다).
  # 성공하면 true, 검증에 걸리면 errors 를 채우고 false.
  def approve(by:, comment:)
    comment = comment.to_s.strip.gsub(/\r\n?/, "\n")
    if comment.blank?
      errors.add(:base, "코멘트가 비어 있어요. 학생에게 보여 줄 코멘트를 적어 주세요.")
      return false
    end
    if comment.length > COMMENT_MAX_LENGTH
      errors.add(:base, "코멘트는 #{COMMENT_MAX_LENGTH}자까지 적을 수 있어요.")
      return false
    end

    self.teacher_comment = comment == ai_comment.to_s.strip ? nil : comment
    self.reviewed_by ||= by
    self.reviewed_at ||= Time.current
    save
  end

  # 작성자 play 화면의 코멘트 영역(dom_id :feedback)을 라이브 교체한다. 코멘트 잡 완료와 담임 승인 양쪽이
  # 부른다. 방송은 부수효과라 실패를 흡수한다(이미 커밋된 상태를 뒤집지 않는다 — Report#broadcast_detail_refresh 관례).
  def broadcast_feedback_refresh
    broadcast_replace_to(
      self,
      target: ActionView::RecordIdentifier.dom_id(self, :feedback),
      partial: "games/sequel/feedback",
      locals: { sequel: self }
    )
  rescue StandardError => e
    Rails.logger.warn("BookSequel#broadcast_feedback_refresh failed for sequel #{id}: #{e.class}: #{e.message}")
  end
end
