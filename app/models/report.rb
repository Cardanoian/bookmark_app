class Report < ApplicationRecord
  include RubricScorable

  belongs_to :user
  belongs_to :classroom
  belongs_to :book, optional: true
  belongs_to :revision_of, class_name: "Report", optional: true
  has_many :revisions, class_name: "Report", foreign_key: :revision_of_id, dependent: :nullify
  has_one :board_post, dependent: :destroy
  has_many :stickers, dependent: :destroy

  has_one_attached :photo
  has_one_attached :drawing
  has_one_attached :audio

  enum :input_mode, { keyboard: 0, wongoji: 1, ocr: 2 }, default: :keyboard
  enum :ai_status, { pending: 0, processing: 1, done: 2, failed: 3 }, default: :pending

  validates :level, inclusion: { in: %w[A B C], allow_nil: true }
  validate :book_reference_present
  validate :attachments_within_limits

  IMAGE_MAX_BYTES = 10.megabytes
  AUDIO_MAX_BYTES = 20.megabytes

  # 첨삭 결과(JSON) 를 문자열/심볼 키 상관없이 안전하게 읽는다.
  def rubric_data
    (rubric || {}).with_indifferent_access
  end

  # 5축 점수 해시(누락축 → 0). 방사형 표시·요약에 사용.
  def rubric_scores
    data = rubric_data
    ReadingDomain::RUBRIC_AXES.index_with { |axis| data[axis].to_i }
  end

  def praise_list
    Array(rubric_data[:praise]).map(&:to_s)
  end

  def fix_list
    Array(rubric_data[:fix]).map(&:to_s)
  end

  # [{ "text" =>, "standard_code" => }, ...]
  def grow_list
    Array(rubric_data[:grow]).filter_map do |entry|
      next unless entry.respond_to?(:to_h)

      entry.to_h.with_indifferent_access
    end
  end

  # 교사가 조정한 5축(없으면 nil 값들).
  def teacher_rubric_scores
    data = (teacher_rubric || {}).with_indifferent_access
    ReadingDomain::RUBRIC_AXES.index_with { |axis| data[axis] }
  end

  # 중간 검사(맞춤법) 신호. spelling 축 점수와 한 줄 안내.
  def spelling_feedback
    score = rubric_data[:spelling]
    return nil if score.nil?

    label =
      case score.to_i
      when 5 then "맞춤법이 아주 정확해요."
      when 4 then "맞춤법이 대체로 정확해요."
      when 3 then "맞춤법을 한 번 더 확인해 볼까요?"
      else "맞춤법·띄어쓰기를 다시 살펴보면 좋겠어요."
      end
    { score: score.to_i, message: label }
  end

  def revision?
    revision_of_id.present?
  end

  # 고쳐쓰기 전/후 간단 비교. 원본과 겹치지 않는 표현을 추린다.
  def diff_against_original
    return nil unless revision? && revision_of

    original_words = tokenize_body(revision_of.body)
    revised_words = tokenize_body(body)
    {
      original_body: revision_of.body.to_s,
      revised_body: body.to_s,
      added: (revised_words - original_words),
      removed: (original_words - revised_words)
    }
  end

  private

  def tokenize_body(text)
    text.to_s.scan(/\p{Word}+/)
  end

  def book_reference_present
    return if book_id.present? || book_title.present?

    errors.add(:base, "도서 또는 책 제목이 필요합니다.")
  end

  def attachments_within_limits
    validate_attachment(:photo, %w[image/], IMAGE_MAX_BYTES)
    validate_attachment(:drawing, %w[image/], IMAGE_MAX_BYTES)
    validate_attachment(:audio, %w[audio/], AUDIO_MAX_BYTES)
  end

  def validate_attachment(name, allowed_prefixes, max_bytes)
    attachment = public_send(name)
    return unless attachment.attached?

    blob = attachment.blob
    unless allowed_prefixes.any? { |prefix| blob.content_type.to_s.start_with?(prefix) }
      errors.add(name, "허용되지 않는 파일 형식입니다.")
    end

    if blob.byte_size.to_i > max_bytes
      errors.add(name, "파일 크기가 너무 큽니다.")
    end
  end
end
