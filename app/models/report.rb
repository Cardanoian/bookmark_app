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

  before_validation :normalize_book_title

  validates :level, inclusion: { in: %w[A B C], allow_nil: true }
  validate :book_reference_present
  validate :attachments_within_limits

  IMAGE_MAX_BYTES = 10.megabytes
  AUDIO_MAX_BYTES = 20.megabytes

  # 학생 학급 학년으로 판별한 학년군 키(:g12/:g34/:g56). AI 첨삭 눈높이 분기에 사용.
  # 학급/학년 미상이면 :g56 으로 폴백(ReadingDomain.band_for 계약).
  def grade_band_key
    ReadingDomain.band_for(classroom&.grade)
  end

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

  # 학생 대면 AI 첨삭 산출물 표시의 **유일한 판정**. 교사가 검토·승인(reviewed)한 뒤에만
  # 첨삭 텍스트·등급을 학생에게 노출한다. 게이트는 레코드 상태만 본다(current_user/policy 금지)
  # — `_report_detail` 은 HTTP 렌더뿐 아니라 뷰어 없는 백그라운드 잡 방송에서도 렌더되기 때문.
  def feedback_visible?
    reviewed? && rubric.present?
  end

  # 학생에게 보여 줄 첨삭 텍스트 정규화 해시. teacher_feedback(교사 편집본) 있으면 그것,
  # 없으면 AI 원본(praise/fix/grow) 폴백. **grow 는 항상 `[{text:, standard_code:}]` 형태**를
  # 보장해 뷰의 해시 접근(`g[:text]`)에서 문자열이 섞여 크래시(`"..."[:text]`)나지 않게 한다.
  # teacher_feedback 은 JSON 왕복 후 문자열 키이므로 with_indifferent_access 로 래핑한다.
  def student_feedback
    source = teacher_feedback.presence&.with_indifferent_access
    if source
      {
        praise: Array(source[:praise]).map(&:to_s),
        fix: Array(source[:fix]).map(&:to_s),
        grow: normalize_grow(source[:grow])
      }
    else
      {
        praise: praise_list,
        fix: fix_list,
        grow: normalize_grow(rubric_data[:grow])
      }
    end
  end

  # 학생 상세(show)의 상세 영역(`dom_id(self,:detail)`)을 실시간 교체한다. show 의
  # `turbo_stream_from self` 구독과 대응. AiReviewJob(첨삭/재첨삭 완료·실패)과
  # Teacher::ReviewsController(승인·승인 후 정정)이 공용한다. **방송 실패는 내부 rescue 로
  # 흡수**한다 — 빼면 방송 실패가 호출부(잡 perform·컨트롤러)의 상위 rescue 로 전파돼 이미
  # 커밋된 리포트가 ai_status:failed 로 뒤집히거나 500 이 난다. 다음 로드에서 레코드 상태로 복원.
  def broadcast_detail_refresh
    broadcast_replace_to(
      self,
      target: ActionView::RecordIdentifier.dom_id(self, :detail),
      partial: "reports/report_detail",
      locals: { report: self }
    )
  rescue StandardError => e
    Rails.logger.warn("Report#broadcast_detail_refresh failed for report #{id}: #{e.class}: #{e.message}")
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

  # grow 엔트리를 항상 `[{text:, standard_code:}]`(심볼 키·문자열 값) 형태로 정규화한다.
  # teacher_feedback(문자열 키·JSON 왕복)·AI rubric(indifferent) 어느 쪽이 소스든 뷰가 동일하게
  # `g[:text]`/`g[:standard_code]` 로 접근할 수 있게 하고, 문자열 엔트리가 섞여도 걸러 크래시를 막는다.
  def normalize_grow(raw)
    Array(raw).filter_map do |entry|
      next unless entry.respond_to?(:to_h)

      data = entry.to_h.with_indifferent_access
      { text: data[:text].to_s, standard_code: data[:standard_code].to_s }
    end
  end

  def tokenize_body(text)
    text.to_s.scan(/\p{Word}+/)
  end

  # 자유입력 책 제목의 앞뒤·중복 공백을 정리(squish)하고 빈 문자열은 nil 로 만든다. 검증·조회
  # (index book_title 필터)가 정규화된 값을 단일 기준으로 쓰게 해 "이중  공백" 같은 레거시 표기가
  # 필터에서 새지 않도록 한다. squish 는 정상 제목을 바꾸지 않으므로 기존 동작에 무해하다.
  def normalize_book_title
    self.book_title = book_title.to_s.squish.presence
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
    content_type = server_identified_content_type(name, blob)
    unless allowed_prefixes.any? { |prefix| content_type.to_s.start_with?(prefix) }
      errors.add(name, "허용되지 않는 파일 형식입니다.")
    end

    if blob.byte_size.to_i > max_bytes
      errors.add(name, "파일 크기가 너무 큽니다.")
    end
  end

  # 멀티파트로 신고된 content_type 은 스푸핑 가능하므로 신뢰하지 않는다(§2.10).
  # 업로드된 실제 바이트의 매직바이트 + 파일명으로 서버에서 재식별한다(declared_type
  # 미사용). 매직바이트가 명확하면 우선하고, 불명확하면 확장자로 폴백한다. 이렇게 하면
  # 클라이언트가 Content-Type 헤더만 image/*·audio/* 로 위조해도 통과할 수 없다.
  # (잔여 리스크: 확장자까지 맞춘 비미디어 파일은 통과 가능 — 브라우저는 선언 타입으로
  #  무해하게 렌더하며 스크립트 실행 벡터가 아니므로 LOW.)
  def server_identified_content_type(name, blob)
    io = pending_upload_io(name)
    return blob.content_type unless io

    io.rewind if io.respond_to?(:rewind)
    Marcel::MimeType.for(io, name: blob.filename.to_s)
  ensure
    io.rewind if io.respond_to?(:rewind)
  end

  # 저장 전(업로드 전) 첨부의 원본 IO 를 구한다. 컨트롤러 업로드는 UploadedFile,
  # 테스트/내부 attach 는 { io: } 해시 형태다. 이미 업로드된 blob·signed id 는
  # 재식별 대상이 아니므로 nil 을 돌려 저장된 식별값으로 폴백하게 한다.
  def pending_upload_io(name)
    attachable = attachment_changes[name.to_s]&.attachable
    case attachable
    when Hash
      io = attachable[:io]
      io if io.respond_to?(:read)
    when ActiveStorage::Blob, String, NilClass
      nil
    else
      attachable if attachable.respond_to?(:read)
    end
  end
end
