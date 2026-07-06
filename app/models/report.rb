class Report < ApplicationRecord
  belongs_to :user
  belongs_to :classroom
  belongs_to :book, optional: true
  belongs_to :revision_of, class_name: "Report", optional: true
  has_many :revisions, class_name: "Report", foreign_key: :revision_of_id, dependent: :nullify

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

  private

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
