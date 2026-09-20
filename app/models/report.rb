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

  # validate: 없는 값(조작한 report[input_mode]=bogus)은 대입 때 ArgumentError(→ 500) 대신 검증 오류가 된다.
  enum :input_mode, { keyboard: 0, wongoji: 1, ocr: 2 }, default: :keyboard, validate: true
  enum :ai_status, { pending: 0, processing: 1, done: 2, failed: 3 }, default: :pending

  # 제출된 글만. 교사 검토 큐·대시보드 집계처럼 "학생이 낸 글"을 세는 모든 지점의 진입 스코프다.
  scope :submitted, -> { where.not(submitted_at: nil) }
  # `review_ready?` 의 SQL 판 — 지금 제출(현재 버전)의 첨삭이 완성된 제출 글. 두 판정은 함께 고친다.
  scope :review_ready, lambda {
    submitted.where(ai_status: :done)
             .where("reports.review_version > 0 AND reports.completed_review_version = reports.review_version")
             .where("reports.rubric IS NOT NULL AND reports.rubric NOT IN ('{}', '[]', 'null', '')")
  }
  # 교사가 **현재 제출의 완성된 첨삭을** 승인한 글(= feedback_visible? 의 SQL 판). 표창장·가정통신문·포트폴리오·
  # 학급 리포트처럼 학생·보호자에게 나가는 인쇄 문서와 학생의 '나의 성장'은 이 경계만 쓴다 — 승인 전 글이나
  # 첨삭 없이 승인된 옛 글이 섞이면 교사가 확인하지 않은 AI 등급·점수가 "대표 독후감"으로 나간다.
  scope :approved, -> { review_ready.where(reviewed: true) }

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

  # 학생 성장 시계열의 최종 점수. 교사 조정값이 있는 축은 그것을 우선하고,
  # 조정하지 않은 축은 승인된 AI 루브릭 점수를 사용한다.
  def final_rubric_scores
    ai_scores = rubric_scores
    adjusted_scores = teacher_rubric_scores
    ReadingDomain::RUBRIC_AXES.index_with do |axis|
      adjusted_scores[axis].nil? ? ai_scores.fetch(axis) : adjusted_scores[axis].to_i
    end
  end

  # 최종 5축(final_rubric_scores)의 단순 평균(소수 첫째 자리). '나의 성장'과 교사 인쇄 문서가 같은 값을 쓴다.
  def final_average
    scores = final_rubric_scores
    (scores.values.sum.to_f / scores.size).round(1)
  end

  # **지금 제출(현재 버전)의 첨삭이 완성됐는가**(BUG_FIX_PLAN F2·F3). 교사 승인(ReportPolicy#approve?)과
  # 학생 공개(feedback_visible?)가 함께 쓰는 단일 판정이다. `ai_status == done && rubric.present?` 만으로는
  # 부족하다 — 고쳐 다시 낸 글에는 **이전 제출의 루브릭**이 그대로 남아 있고, 새 첨삭이 끝나기 전에도 그
  # 조건이 참이 된다. 그래서 "결과를 확정한 버전(completed_review_version)이 지금 버전(review_version)과
  # 같은가"를 본다. 초안(버전 0)·대기·처리 중·실패는 모두 거짓이다. 규칙 기반 폴백도 정상 완료면 done 이다.
  def review_ready?
    submitted? && done? && rubric.present? &&
      review_version.to_i.positive? && completed_review_version == review_version
  end

  # 첨삭을 같은 버전으로 다시 요청할 수 있는 글인가 — 현재 버전이 실패로 끝났거나, 대기·처리 중인 채로
  # REVIEW_STALLED_AFTER 넘게 멈춰 있다(큐 적재 실패·워커 중단). 버전을 올리지 않으므로 늦게 끝난 원래
  # 작업과 겹쳐도 AiReviewJob 의 확정 조건이 한 번만 반영한다.
  REVIEW_STALLED_AFTER = 10.minutes

  def review_retryable?
    return false if draft? || review_ready?
    # 제출됐는데 버전이 0 인 글(수동 이관 흔적)은 다시 요청해도 예약되지 않는다 — 버튼을 보이지 않는다
    # (reports:audit_review_versions 가 목록화하고, 버전을 바로잡은 뒤 재예약한다).
    return false unless review_version.to_i.positive?

    failed? || updated_at.nil? || updated_at < REVIEW_STALLED_AFTER.ago
  end

  # 학생 대면 AI 첨삭 산출물 표시의 **유일한 판정**. 교사가 **현재 버전의 완성된 첨삭**을 검토·승인한
  # 뒤에만 첨삭 텍스트·등급을 학생에게 노출한다. 예전 판정(`reviewed? && rubric.present?`)은 첨삭이
  # 만들어지기 전에 승인된 글을, 첨삭이 저장되는 순간 교사가 읽지 않은 채 공개했다(F3).
  # 게이트는 레코드 상태만 본다(current_user/policy 금지)
  # — `_report_detail` 은 HTTP 렌더뿐 아니라 뷰어 없는 백그라운드 잡 방송에서도 렌더되기 때문.
  def feedback_visible?
    reviewed? && review_ready?
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

  # 제출·재제출 기록(DB 쓰기만). **새 첨삭 요청의 버전을 발급해 돌려준다** — 부른 쪽은 커밋이 끝난 뒤
  # 바로 그 버전으로 AiReviewJob 을 예약한다(예약 직전에 다시 읽은 버전으로 바꾸지 말 것 — 그사이 또
  # 제출됐다면 그 제출이 제 버전의 작업을 따로 예약한다). 새 글 제출·초안 첫 제출·OCR 뒤 제출·고쳐쓰기·
  # 재제출이 모두 이 한 곳을 거친다. 본문 저장과 같은 트랜잭션(잠금) 안에서 부른다.
  #
  # 검토 상태를 완전히 되돌린다(미검토 + 교사 편집본 비움): 승인본을 학생이 고쳐 다시 내면 첨삭 비공개
  # 게이트(feedback_visible?)에 다시 들어가고 담임 검토 목록으로 돌아온다. 옛 본문을 대상으로 한 교사 편집본
  # (teacher_feedback/teacher_rubric/teacher_comment)은 스테일이라 함께 비운다 — 안 비우면 재승인 뒤
  # student_feedback 이 옛 teacher_feedback 을 우선 노출한다. 버전이 오르므로 완료 버전은 새 결과가
  # 확정될 때까지 현재 버전과 어긋난다(= review_ready? 거짓 — 남아 있는 이전 루브릭은 승인·공개되지 않는다).
  #
  # `submitted_at` 은 **여기가 유일한 기록 지점**이다. OCR 초안은 사진 업로드 시점에 이미 영속화되므로
  # "레코드가 있다 = 제출했다"가 성립하지 않는다(submitted? 주석). 재제출은 시각을 갱신하지 않는다 —
  # 덮어쓰면 "언제 처음 냈는가"라는 되살릴 수 없는 사실만 잃는다.
  #
  # **메모리의 값에 기대지 않고 DB 에 쓴다**(update_all + 버전은 SQL 에서 +1). `update!` 는 바뀐 칸만 UPDATE 에
  # 싣는데, 이 객체를 읽은 뒤에 다른 요청이 승인했다면 메모리의 reviewed 는 여전히 false 라 "false 로 되돌리기"가
  # 변경으로 잡히지 않아 빠진다 — 새 제출이 승인된 채 남는다(승인·재제출 경합 테스트가 잡았다).
  def record_submission!
    transaction do
      now = Time.current
      scope = self.class.where(id: id)
      scope.update_all(ai_status: self.class.ai_statuses[:pending], reviewed: false, reviewed_at: nil,
                       teacher_feedback: nil, teacher_rubric: nil, teacher_comment: nil, updated_at: now)
      scope.where(submitted_at: nil).update_all(submitted_at: now)
      scope.update_all("review_version = review_version + 1")
      reload
      # 승인이 풀리는 지점이므로 공유도 함께 걷는다. 안 걷으면 학생이 승인본을 고쳐 다시 낸 순간
      # **미검토 본문이 게시판에 그대로 공개된 채** 남는다(ReportPolicy#share? 의 승인 게이트를 우회하는 구멍).
      unshare! if shared?
      # 검색으로 고른 책은 낸 순간 정식 카탈로그로 올린다(초안 동안은 검색 캐시). no-op 이면 무해.
      book&.promote_from_search!
    end
    review_version
  end

  # 공유 해제 + 게시물 파기. board_post 파기 → 응원(cheers)이 cascade 삭제된다. 스티커는 report 소속이라 유지.
  # cheers_count 는 콜백 없는 수동 카운터라 여기서 0 으로 초기화해야 재공유·스탯 집계가 어긋나지 않는다
  # (ReadingStats#cheers_received 과대 집계 방지).
  def unshare!
    board_post&.destroy
    update!(shared: false, cheers_count: 0)
  end

  # 교사 승인. **교사가 화면에서 확인한 버전(seen_version)의 완성된 첨삭만** 승인한다(F3 §5.2).
  # 반환: :approved(이번 요청이 승인함) / :already(같은 버전이 이미 승인됨 — 시각·보상·방송을 다시 일으키지
  # 않는다) / :stale(화면을 연 뒤 학생이 다시 냈거나 버전을 싣지 않은 요청 — 서버의 현재 버전으로 채워
  # 승인하지 않는다) / :not_ready(대기·처리 중·실패·초안).
  # 판단은 트랜잭션 안에서 다시 읽은 값으로 하고, 전이는 조건부 UPDATE 의 영향 행 수로 확인한다 —
  # 재제출(record_submission!)과 겹쳐도 새 제출이 승인된 채 남지 않는다. 후속 처리(뱃지·미션·방송)는
  # :approved 를 받은 호출부가 커밋 뒤에 한다.
  def approve!(seen_version:)
    seen = seen_version.to_s[/\A\d{1,9}\z/]&.to_i # 10진수만(Integer("010") 은 8 이다). 없거나 숫자가 아니면 nil.
    outcome = transaction do
      lock! # SQLite 에서는 재조회다(트랜잭션이 BEGIN IMMEDIATE 로 쓰기 잠금을 먼저 잡는다).
      next :stale unless seen == review_version
      next :already if reviewed?
      next :not_ready unless review_ready?

      now = Time.current
      approved = self.class.where(id: id, review_version: seen, completed_review_version: seen, reviewed: false)
                     .update_all(reviewed: true, reviewed_at: now, updated_at: now)
      approved == 1 ? :approved : :stale
    end
    reload if outcome == :approved
    outcome
  end

  # 학생 상세(show)의 상세 영역(`dom_id(self,:detail)`)을 실시간 교체한다. show 의
  # `turbo_stream_from self` 구독과 대응. AiReviewJob(첨삭/재첨삭 완료·실패)과
  # Teacher::ReviewsController(승인·승인 후 정정)이 공용한다. **방송 실패는 내부 rescue 로
  # 흡수**한다 — 빼면 방송 실패가 호출부(잡 perform·컨트롤러)의 상위 rescue 로 전파돼 이미
  # 커밋된 리포트가 ai_status:failed 로 뒤집히거나 500 이 난다. 다음 로드에서 레코드 상태로 복원.
  #
  # **방송 직전에 DB 에서 다시 읽은 글로 그린다**(BUG_FIX_PLAN §4.4). 부른 쪽이 들고 있던 객체가 그사이 낡았을 수
  # 있다 — 승인 직후 학생이 다시 냈다면 메모리의 `reviewed=true`·옛 버전으로 그린 파셜이 **이전 제출의 첨삭**을
  # 학생의 열린 화면에 밀어 넣는다. 파셜의 공개 판정(feedback_visible?)은 다시 읽은 글에 대해 한다.
  def broadcast_detail_refresh
    latest = self.class.find_by(id: id)
    return unless latest

    latest.broadcast_replace_to(
      latest,
      target: ActionView::RecordIdentifier.dom_id(latest, :detail),
      partial: "reports/report_detail",
      locals: { report: latest }
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

  # 학생이 "제출하기"를 눌러 첨삭·검토 흐름에 올린 글인지. **`ai_status` 로 추론하지 말 것** —
  # OCR 초안은 학생이 제출하기 전에 이미 영속화되고 `OcrJob` 이 판독을 마치면 `ai_status: :done`
  # 이 되므로, 그 컬럼만으로는 "첨삭까지 끝난 글"과 구별되지 않는다(교사 큐에 초안이 새어
  # 들어가 rubric 없이 승인되던 결함의 원인). 고쳐쓰기(revise) 초안도 원본의 rubric·done 을
  # 물려받으므로 같은 이유로 여기 걸린다.
  def submitted?
    submitted_at.present?
  end

  # 아직 제출하지 않은 초안(OCR 판독 대기·판독 완료 후 미제출, 고쳐쓰기 미편집).
  def draft?
    submitted_at.nil?
  end

  # 자동 저장(과 임시 저장 버튼)을 붙일 초안인지. **사진(OCR) 초안의 첫 제출 화면은 뺀다** — 그
  # 화면은 "제출하기를 눌러야 선생님 첨삭이 시작돼요"를 못박고 있어, '저장했어요' 표시가 아이에게
  # '다 됐다'로 읽히면 첨삭이 영영 안 붙는다(09-04 에 임시 저장 버튼을 뺀 것과 같은 이유).
  # 고쳐쓰기 초안은 원본이 사진이어도 대상이다 — 이미 글자로 옮겨진 본문을 고치는 화면이라서다.
  # 원본을 지운 고쳐쓰기 초안(revision_of_id 가 nil)도 원본의 rubric 을 물려받아 여기 든다.
  def autosave_eligible?
    draft? && !(ocr? && !revision? && rubric.blank?)
  end

  # 선생님께 **처음** 내는 글인지(편집 화면의 '제출하기' 표시와 ReportsController 의 첫 제출 판정이
  # 함께 쓴다). 첨삭 받은 적 없는 글(OCR 초안·자동 저장된 새 초안)과, **원본을 지운 고쳐쓰기 초안**이다.
  # 원본을 지우면 revision_of_id 는 nil 이 되지만(has_many :revisions, dependent: :nullify) rubric 은
  # 원본에서 복사돼 남는다 — rubric 만 보면 "이미 첨삭 받은 글"로 오인해, '수정하기'를 눌러도
  # 선생님께 가지 않고 다시 열면 버튼까지 잠겼다(2026-09-13 리뷰에서 재현).
  def first_submission?
    !revision? && (rubric.blank? || draft?)
  end

  # 자동 저장이 "내가 마지막으로 본 초안"을 서버에 알리는 표. 다른 탭·기기가 그사이 초안을 더 고쳤으면
  # 값이 달라져 서버가 저장을 거절한다(ReportsController#stale_draft_version?). 초 단위로는 같은 초 안의
  # 두 저장을 가르지 못하므로 마이크로초까지 쓴다.
  def draft_version
    updated_at&.utc&.iso8601(6)
  end

  # 표시할 OCR 원본 사진(ActiveStorage::Attached::One 또는 nil). 고쳐쓰기(revise)는 부모의
  # `input_mode` 는 복사하지만 photo 는 승계하지 않으므로, 사진이 없으면 `revision_of` 체인을
  # 거슬러 올라가 최초 촬영본(root)을 찾는다 — 그래야 교사가 고쳐쓴 글도 원문 사진과 대조할 수 있다.
  # revise 는 항상 더 오래된 부모(id 단조감소)를 가리켜 사이클이 불가능하지만, 손상 데이터에서도
  # 뷰·바이트 서빙이 무한루프에 빠지지 않도록 depth cap(10)을 둔다. 렌더당 belongs_to 반복 쿼리를
  # 막기 위해 결과를 memoize 한다(hot path).
  def display_photo
    return @display_photo if defined?(@display_photo)

    node = self
    10.times do
      break if node.nil? || node.photo.attached?

      node = node.revision_of
    end
    @display_photo = node&.photo&.attached? ? node.photo : nil
  end

  # 사진 표시 게이트. revise 가 `input_mode` 를 복사하므로 고쳐쓴 글도 `ocr?` 다
  # (별도 `revision_of&.ocr?` 절이 필요 없다).
  def display_photo?
    ocr? && display_photo.present?
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
