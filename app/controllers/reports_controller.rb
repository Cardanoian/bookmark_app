class ReportsController < ApplicationController
  before_action :set_report, only: [ :show, :edit, :update, :revise, :share ]

  PER_PAGE = 20

  # 학생은 자기 글, 교사는 담당 학급 글(정책 스코프). 무제한 목록을 페이지네이션한다.
  def index
    authorize Report
    @page = [ params[:page].to_i, 1 ].max
    records = policy_scope(Report).includes(:book, :user).order(created_at: :desc)
                .limit(PER_PAGE + 1).offset((@page - 1) * PER_PAGE).to_a
    @has_next_page = records.size > PER_PAGE
    @reports = records.first(PER_PAGE)
  end

  def show
    authorize @report
  end

  def new
    @report = Current.user.reports.new(prefill_attributes)
    authorize @report
  end

  def create
    @report = Current.user.reports.new(report_params)
    @report.classroom = Current.user.classroom
    link_participation(@report)
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

  # 우수작 공유(P5.3): 실제 토글. 공유 중이면 해제(게시물 파기), 아니면 공유(게시물 1개 생성).
  # 뷰 버튼 라벨("공유 취소"/"우수작 공유")과 동작을 일치시킨다.
  def share
    authorize @report, :share?

    if @report.shared?
      # board_post 파기 → 응원(cheers)이 cascade 삭제된다. 스티커는 report 소속이라 유지.
      # cheers_count 는 콜백 없는 수동 카운터라 여기서 0 으로 초기화해야 재공유·스탯 집계가
      # 어긋나지 않는다(ReadingStats#cheers_received 과대 집계 방지).
      @report.board_post&.destroy
      @report.update!(shared: false, cheers_count: 0)
      redirect_to @report, notice: "공유를 취소했어요."
    else
      @report.update!(shared: true)
      board_post = BoardPost.find_or_create_by!(report: @report)
      redirect_to board_post_path(board_post), notice: "우수작으로 공유했어요."
    end
  end

  private

  def set_report
    @report = Report.find(params[:id])
  end

  # 새 독후감 기본값 + 위저드(P5.5) 초안 프리필(book_title/body).
  def prefill_attributes
    attrs = { input_mode: params[:input_mode].presence || "keyboard" }
    attrs.merge!(params.require(:report).permit(:book_title, :body).to_h) if params[:report].present?
    attrs
  end

  # 미션/챌린지 참여 후 첫 작성 글에 mission_id/challenge_id 를 연결한다(P4.11).
  # 참여 플래그는 세션에서 소비(1회성). 진화/뱃지 엔진(ReadingStats)이 이를 집계한다.
  def link_participation(report)
    if (mission_id = session.delete(:active_mission_id))
      mission = Mission.find_by(id: mission_id)
      report.mission_id = mission.id if mission && mission.classroom_id == Current.user.classroom_id
    end

    if (challenge_id = session.delete(:active_challenge_id))
      report.challenge_id = challenge_id if Challenge.exists?(id: challenge_id)
    end
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
