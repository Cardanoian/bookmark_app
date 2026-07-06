class OcrController < ApplicationController
  # 사진 업로드 → 손글씨 OCR 초안. Gemini 키가 없으면 사진 모드 자체가 없어야
  # 하므로 서버에서도 거부한다(P3.5). 성공 시 OcrJob 예약 + Turbo Stream 응답.
  def create
    unless ocr_available?
      redirect_back fallback_location: new_report_path,
        alert: "사진 모드를 사용할 수 없어요. 키보드나 원고지로 입력해 주세요."
      return
    end

    @report = find_or_build_draft
    authorize @report, :update?

    if params.dig(:ocr, :photo).blank?
      redirect_back fallback_location: edit_report_path(@report), alert: "사진을 선택해 주세요."
      return
    end

    @report.photo.attach(params[:ocr][:photo])
    @report.update!(ai_status: :pending, input_mode: :ocr)
    OcrJob.perform_later(@report)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to edit_report_path(@report), notice: "사진을 읽는 중이에요." }
    end
  end

  private

  # 기존 초안(내 글) 을 쓰거나, 없으면 사진 독후감 초안을 새로 만든다.
  def find_or_build_draft
    if params.dig(:ocr, :report_id).present?
      Current.user.reports.find(params[:ocr][:report_id])
    else
      Current.user.reports.create!(
        classroom: Current.user.classroom,
        input_mode: :ocr,
        book_title: params.dig(:ocr, :book_title).presence || "사진 독후감"
      )
    end
  end
end
