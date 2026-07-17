class Teacher::ReviewsController < ApplicationController
  before_action :set_report, only: [ :show, :update, :approve, :verify ]
  # index·batch_approve 는 ensure_reviewer! 역할 게이트로 담임 큐를 스코프한다(개별 리소스 authorize 없음).
  skip_after_action :verify_authorized, only: [ :index, :batch_approve ]

  # 담임 학급의 미검토 큐(첨삭 완료된 독후감).
  def index
    ensure_reviewer!
    @reports = pending_scope.includes(:user, :book).order(created_at: :asc)
  end

  def show
    authorize @report, :review?
  end

  # 5축 ±조정 + 교사 코멘트 저장. md §4 "최종 등급을 변경한 뒤" 해금 재평가 지점.
  def update
    authorize @report, :review?

    if @report.update(review_params)
      discovered = evaluate_monster_unlocks(@report.user)
      redirect_to teacher_review_path(@report), notice: with_discovery("검토 내용을 저장했어요.", discovered)
    else
      render :show, status: :unprocessable_entity
    end
  end

  # 승인 → reviewed 기록 + 학생 화면 실시간 갱신(P3.9).
  def approve
    authorize @report, :approve?

    discovered = finalize_approval(@report)
    redirect_to teacher_reviews_path,
                notice: with_discovery("#{@report.user.name} 학생의 독후감을 승인했어요.", discovered)
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

    discovered = []
    pending_scope.where(id: Array(params[:report_ids])).find_each do |report|
      next unless ReportPolicy.new(Current.user, report).approve?

      discovered.concat(finalize_approval(report))
    end
    redirect_to teacher_reviews_path, notice: with_discovery("선택한 독후감을 승인했어요.", discovered)
  end

  private

  # 승인 확정: reviewed 기록 + 학생 실시간 갱신 + 승인 시점에 바뀌는 승인-기준
  # 진화/뱃지 조건(reports·a_grades 등) 재계산 + 몬스터 해금 재평가.
  # 반환: 이번 승인으로 새로 발견한 몬스터(UserMonster) 목록(호출부가 flash 안내에 사용).
  def finalize_approval(report)
    report.update!(reviewed: true, reviewed_at: Time.current)
    broadcast_to_student(report)
    report.user.refresh_badges!
    report.user.check_evolution!
    evaluate_monster_unlocks(report.user)
  end

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
      locals: { report: report, show_delete: true }
    )
  end
end
