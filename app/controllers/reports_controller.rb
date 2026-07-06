class ReportsController < ApplicationController
  before_action :set_report, only: [ :show, :edit, :update, :revise, :share ]

  # 학생은 자기 글, 교사는 담당 학급 글(정책 스코프).
  def index
    @reports = policy_scope(Report).includes(:book, :user).order(created_at: :desc)
    authorize Report
  end

  def show
    authorize @report
  end

  def new
    @report = Current.user.reports.new(input_mode: params[:input_mode].presence || "keyboard")
    authorize @report
  end

  def create
    @report = Current.user.reports.new(report_params)
    @report.classroom = Current.user.classroom
    authorize @report

    if @report.save
      submit_for_review(@report)
      redirect_to @report, notice: "독후감을 제출했어요. AI 선생님이 첨삭 중이에요."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @report
  end

  def update
    authorize @report

    if @report.update(report_params)
      submit_for_review(@report) if resubmit?
      redirect_to @report, notice: "독후감을 수정했어요."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # 고쳐쓰기: 원본을 잇는 새 독후감을 만들고 재첨삭을 예약한다(P3.10).
  def revise
    authorize @report, :revise?

    revision = Current.user.reports.new(
      classroom: @report.classroom,
      book_id: @report.book_id,
      book_title: @report.book_title,
      body: @report.body,
      input_mode: @report.input_mode,
      revision_of: @report,
      prev_avg: @report.avg
    )

    if revision.save
      submit_for_review(revision)
      redirect_to edit_report_path(revision), notice: "고쳐쓰기를 시작해요. 더 좋게 다듬어 볼까요?"
    else
      redirect_to @report, alert: revision.errors.full_messages.to_sentence
    end
  end

  def share
    authorize @report, :share?
    @report.update(shared: !@report.shared)
    redirect_to @report, notice: @report.shared? ? "우수작 게시판에 공유했어요." : "공유를 취소했어요."
  end

  private

  def set_report
    @report = Report.find(params[:id])
  end

  def report_params
    params.require(:report).permit(:book_id, :book_title, :body, :input_mode, :photo, :drawing, :audio)
  end

  # 제출/재제출: 재첨삭 대기 상태로 돌리고 AiReviewJob 을 예약한다.
  def submit_for_review(report)
    report.update!(ai_status: :pending)
    AiReviewJob.perform_later(report)
  end

  # 작성자가 본문을 바꿔 다시 낸 경우에만 재첨삭.
  def resubmit?
    Current.user.id == @report.user_id && @report.saved_change_to_body?
  end
end
