class OcrController < ApplicationController
  # 사진 업로드 → 손글씨 OCR 초안. OCR 은 Gemini 를 쓰므로 Gemini 키가 없으면 사진 모드 자체가 없어야
  # 하므로 서버에서도 거부한다(P3.5). 거부 검사는 모두 draft 생성 이전에 배치해
  # book_reference_present 실패로 인한 500·빈 첨부 고아 draft 를 막고, 성공 시
  # OcrJob 예약 후 compose(edit) 화면으로 redirect 한다.
  def create
    unless ocr_available?
      # 기능 플래그(Gemini 키) 비활성 조기 거부 — 리소스에 도달하기 전이라 인가 대상이 없다.
      skip_authorization
      redirect_back fallback_location: new_report_path,
        alert: "사진 모드를 사용할 수 없어요. 키보드로 입력해 주세요."
      return
    end

    # 보호자 AI 활용 동의 게이트(P1-1). 미동의 학생은 손글씨 사진(PII)을 Gemini 로 보내지 않도록
    # draft 생성 전에 조기 거부한다(_mode_chooser 의 사진 카드 은닉과 짝 — URL 직접 요청 방어).
    unless Current.user&.ai_consented?
      skip_authorization
      redirect_back fallback_location: new_report_path,
        alert: "보호자 AI 활용 동의가 없어 사진 모드를 쓸 수 없어요. 키보드로 입력해 주세요."
      return
    end

    # 유효 book_id 계산(가드·draft 공용). 자동완성이 채운 book_id 를 우선 검증하고, 없으면
    # 검색 버튼으로 고른 원격 책의 remote_isbn 을 제출 시 등록(캐시-우선·비차단)해 링크한다.
    # register 는 raise 하지 않고 nil 로 degrade 하므로(무키·미일치·실패) 등록 실패는 아래
    # 가드에서 book_title 폴백으로 통과한다. remote_isbn 은 컬럼이 아니라 permit 하지 않고
    # params.dig 로만 소비한다.
    book_id = resolved_book_id(params.dig(:ocr, :book_id)) ||
      register_and_promote(params.dig(:ocr, :remote_isbn))

    # 도서 참조 가드 — draft 생성 전에 배치. 유효 book_id(실존/등록 Book)·book_title 이 모두
    # 없으면 가짜 "사진 독후감" 없이 조기 거부한다(book_reference_present 실패로 인한 RecordInvalid 500 차단).
    if book_id.nil? && params.dig(:ocr, :book_title).blank?
      skip_authorization
      redirect_back fallback_location: new_report_path(input_mode: :ocr),
        alert: "책 제목을 먼저 입력해 주세요."
      return
    end

    # 사진 존재 가드 — draft 생성 전에 배치(빈 첨부로 태어난 고아 draft 방지).
    if params.dig(:ocr, :photo).blank?
      skip_authorization
      redirect_back fallback_location: new_report_path(input_mode: :ocr),
        alert: "사진을 선택해 주세요."
      return
    end

    @report = find_or_build_draft(book_id)
    authorize @report, :update?

    @report.photo.attach(params[:ocr][:photo])
    @report.update!(ai_status: :pending, input_mode: :ocr)
    OcrJob.perform_later(@report)

    # Turbo 가 302 를 따라 compose(edit) 화면으로 Visit → editor 채널 구독 → OcrJob 방송이 본문을 채운다.
    redirect_to edit_report_path(@report), notice: "사진을 읽고 있어요. 잠시만 기다려 주세요."
  end

  private

  # 기존 초안(내 글) 을 쓰거나, 없으면 사진 독후감 초안을 새로 만든다. 도서 참조 가드를 이미
  # 통과했으므로 book_id/book_title 중 하나는 유효하다("사진 독후감" placeholder 불필요).
  # book_id 는 create 에서 계산한 값(자동완성 검증 또는 제출 시 등록 결과)을 그대로 받는다.
  def find_or_build_draft(book_id)
    if params.dig(:ocr, :report_id).present?
      Current.user.reports.find(params[:ocr][:report_id])
    else
      Current.user.reports.create!(
        classroom: Current.user.classroom,
        input_mode: :ocr,
        book_id: book_id,
        book_title: params.dig(:ocr, :book_title).presence
      )
    end
  end

  # 자동완성이 채운 book_id 를 검증한다. 공백·위조·스테일 id 는 nil 로 무시한다.
  # ReportsController#resolved_book_id 와 동일 패턴이나 private 라 공유 불가해 별도 구현.
  def resolved_book_id(raw)
    id = raw.presence
    return nil if id.nil?

    Book.exists?(id) ? id : nil
  end

  # 검색 버튼으로 고른 원격 책을 제출 시 등록(캐시-우선·비차단)하고, 검색해서 독후감을 쓴 책은
  # 정식 카탈로그(recommended)로 즉시 승격해 book_id 를 돌려준다(작성 즉시 등록 — 검색·게임·발견
  # 노출). register 는 nil degrade 이므로 실패 시(무키·미일치) nil → 위 도서 참조 가드가
  # book_title 폴백으로 처리한다. ReportsController#report_params_with_registered_book 미러.
  def register_and_promote(isbn)
    book = Books::SearchService.new.register(isbn)
    return nil unless book

    book.promote_from_search!
    book.id
  end
end
