class Teacher::ReviewsController < ApplicationController
  before_action :set_report, only: [ :show, :update, :approve, :verify ]

  # 담임 학급의 미검토 큐(첨삭 완료된 독후감).
  def index
    ensure_reviewer!
    @reports = pending_scope.includes(:user, :book).order(created_at: :asc)
  end

  def show
    authorize @report, :review?
  end

  # 5축 ±조정 + 교사 코멘트 저장.
  def update
    authorize @report, :review?

    if @report.update(review_params)
      redirect_to teacher_review_path(@report), notice: "검토 내용을 저장했어요."
    else
      render :show, status: :unprocessable_entity
    end
  end

  # 승인 → reviewed 기록 + 학생 화면 실시간 갱신(P3.9).
  def approve
    authorize @report, :approve?

    @report.update!(reviewed: true, reviewed_at: Time.current)
    broadcast_to_student(@report)
    redirect_to teacher_reviews_path, notice: "#{@report.user.name} 학생의 독후감을 승인했어요."
  end

  # 진위·표절 보조(교사용). 결과를 화면에 노출(P3.11).
  def verify
    authorize @report, :verify?

    result = Ai::VerifyService.new.call(@report)
    @verify = result.merge(similarity: Ai::VerifyService.max_similarity(@report))
    render :show
  end

  def batch_approve
    ensure_reviewer!

    pending_scope.where(id: Array(params[:report_ids])).find_each do |report|
      next unless ReportPolicy.new(Current.user, report).approve?

      report.update!(reviewed: true, reviewed_at: Time.current)
      broadcast_to_student(report)
    end
    redirect_to teacher_reviews_path, notice: "선택한 독후감을 승인했어요."
  end

  private

  def set_report
    @report = Report.find(params[:id])
  end

  def review_params
    permitted = params.require(:report).permit(:teacher_comment, teacher_rubric: ReadingDomain::RUBRIC_AXES)
    permitted[:teacher_rubric] = permitted[:teacher_rubric].to_h.transform_values(&:to_i) if permitted[:teacher_rubric].present?
    permitted
  end

  # 담임 학급의 미검토 독후감(첨삭 완료분).
  def pending_scope
    Report.where(classroom_id: Classroom.where(teacher_id: Current.user.id).select(:id), reviewed: false)
  end

  def ensure_reviewer!
    raise Pundit::NotAuthorizedError unless Current.user.teacher? || Current.user.superadmin?
  end

  def broadcast_to_student(report)
    report.broadcast_replace_to(
      [ report.user, :reports ],
      target: ActionView::RecordIdentifier.dom_id(report),
      partial: "reports/report",
      locals: { report: report }
    )
  end
end
