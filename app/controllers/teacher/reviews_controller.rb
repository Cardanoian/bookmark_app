class Teacher::ReviewsController < ApplicationController
  before_action :set_report, only: [ :show, :update, :approve, :verify ]
  # index·batch_approve 는 ensure_reviewer! 역할 게이트로 담임 큐를 스코프한다(개별 리소스 authorize 없음).
  skip_after_action :verify_authorized, only: [ :index, :batch_approve ]

  # 담임 학급의 미검토 큐(첨삭 완료된 독후감).
  def index
    ensure_reviewer!
    @reports = pending_scope
      .includes(:user, :book, photo_attachment: :blob, revision_of: { photo_attachment: :blob })
      .order(created_at: :asc)
  end

  def show
    authorize @report, :review?
  end

  # 5축 ±조정 + 교사 코멘트 저장. md §4 "최종 등급을 변경한 뒤" 해금 재평가 지점.
  def update
    authorize @report, :review?

    if @report.update(review_params)
      # 미승인(reviewed false) 편집은 방송하지 않는다(학생 비노출 유지). 승인 후 정정(reviewed true)
      # 은 학생이 이미 볼 수 있는 첨삭이므로 즉시 라이브 반영해 스테일을 막는다.
      @report.broadcast_detail_refresh if @report.reviewed?
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
    # 검색 캐시(searched)로 유입된 도서라도 승인 독후감이 붙으면 정식 카탈로그로 승격해
    # 독서활동 허브·자동완성·발견에서 정상 도서로 취급되게 한다(Book#promote_from_search!, 멱등).
    report.book&.promote_from_search!
    broadcast_to_student(report)
    # 승인 순간 학생의 열린 show 상세를 라이브로 갱신해 승인·편집된 첨삭·등급을 즉시 노출한다
    # (reviewed 로 전이하는 지점이라 항상 방송; 내부 rescue 로 방송 실패가 승인을 뒤집지 않음).
    report.broadcast_detail_refresh
    report.user.refresh_badges!
    report.user.check_evolution!
    # 미션 진행 평가(menu_refactor 심화 §2.A.3). M5: evaluate_monster_unlocks 앞에 두어 같은 요청에서
    # 미션완료→몬스터해금이 즉시 반영되게 하고, 반환값은 그대로 evaluate_monster_unlocks(discovered
    # 배열)로 유지한다(batch_approve 의 discovered.concat 의존 — 반환값 바뀌면 크래시).
    Missions::EvaluateProgress.new(report.user).on_report_approved(report)
    # 챌린지 진행 평가(챌린지 목표화). 미션과 동형으로 몬스터 해금 앞에 둔다(같은 요청 반영).
    Challenges::EvaluateProgress.new(report.user).on_report_approved(report)
    evaluate_monster_unlocks(report.user)
  end

  def set_report
    @report = Report.find(params[:id])
  end

  def review_params
    permitted = params.require(:report).permit(:teacher_comment, teacher_rubric: ReadingDomain::RUBRIC_AXES)
    permitted[:teacher_rubric] = permitted[:teacher_rubric].to_h.transform_values(&:to_i) if permitted[:teacher_rubric].present?
    if (feedback = build_teacher_feedback)
      permitted[:teacher_feedback] = feedback
    end
    permitted
  end

  # 교사 첨삭 텍스트 편집을 정규화 저장 형태 `{praise:[], fix:[], grow:[{text:,standard_code:}]}` 로
  # 조립한다. 칭찬/보완은 줄단위 textarea → 문자열 배열. 성장은 항목별 고정 입력이며 **text 만** 취하고
  # **standard_code 는 폼 입력을 신뢰하지 않고 `@report.rubric` 원본 grow[i] 의 코드로 서버에서 재설정**
  # 한다(위조·오정렬 이중 방지). 중첩 grow 파라미터는 문자열 인덱스 해시(`{"0"=>{...}}`, 배열 아님)이므로
  # 정수 인덱스로 정렬해 원본 grow 와 zip 한다.
  def build_teacher_feedback
    raw = params.dig(:report, :teacher_feedback)
    return nil if raw.blank?

    original_grow = @report.grow_list
    grow_params = raw[:grow]
    grow =
      if grow_params.respond_to?(:keys)
        grow_params.to_unsafe_h.sort_by { |index, _| index.to_i }.map.with_index do |(_, attrs), i|
          {
            text: attrs[:text].to_s,
            standard_code: original_grow[i] ? original_grow[i][:standard_code].to_s : ""
          }
        end
      else
        []
      end

    {
      praise: split_feedback_lines(raw[:praise]),
      fix: split_feedback_lines(raw[:fix]),
      grow: grow
    }
  end

  # 줄단위 textarea 입력을 문자열 배열로. 빈 줄·앞뒤 공백은 제거한다.
  def split_feedback_lines(text)
    text.to_s.split("\n").map(&:strip).reject(&:blank?)
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
