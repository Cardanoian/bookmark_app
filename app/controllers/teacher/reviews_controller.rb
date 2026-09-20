class Teacher::ReviewsController < ApplicationController
  before_action :set_report, only: [ :show, :update, :approve ]
  # index·batch_approve 는 ensure_reviewer! 역할 게이트로 담임 목록을 스코프한다(개별 리소스 authorize 없음).
  skip_after_action :verify_authorized, only: [ :index, :batch_approve ]

  PER_PAGE = 20
  # 목록 상단 필터. 미지정·위조값은 pending(미검토)으로 폴백해 교사의 기본 워크플로를 유지한다.
  STATUS_FILTERS = %w[all pending reviewed].freeze
  # 저장·승인을 받지 않은 까닭(교사 안내). 버전이 없거나 다른 요청은 :stale 로 안내한다.
  REJECTION_NOTICES = {
    stale: "학생이 그사이 글을 다시 냈어요. 최신 글과 첨삭을 확인한 뒤 다시 해 주세요.",
    not_ready: "아직 첨삭이 준비되지 않은 글이에요. 첨삭이 끝난 뒤에 승인하거나 저장할 수 있어요."
  }.freeze

  # 담임 학급의 검토 목록. 기본은 미검토지만 status 로 검토완료·전체도 열람한다.
  # 검토완료가 합류하면 1년치가 수백 행이 되므로 페이지네이션한다(reports#index 관용구).
  def index
    ensure_reviewer!
    @status = STATUS_FILTERS.include?(params[:status]) ? params[:status] : "pending"
    @page = [ params[:page].to_i, 1 ].max

    @pending_count = classroom_scope.where(reviewed: false).count
    @reviewed_count = classroom_scope.where(reviewed: true).count
    @total_count = @pending_count + @reviewed_count

    records = status_scope(@status)
      .includes(:user, :book, photo_attachment: :blob, revision_of: { photo_attachment: :blob })
      .limit(PER_PAGE + 1).offset((@page - 1) * PER_PAGE).to_a
    @has_next_page = records.size > PER_PAGE
    @reports = records.first(PER_PAGE)
  end

  def show
    authorize @report, :review?
  end

  # 5축 ±조정 + 교사 코멘트 저장. md §4 "최종 등급을 변경한 뒤" 해금 재평가 지점.
  #
  # **교사가 화면에서 확인한 버전에만 저장한다**(BUG_FIX_PLAN F3 §5.2). 폼이 실어 온 review_version 이 지금
  # 버전과 다르면(화면을 연 뒤 학생이 다시 냈다) 이전 글을 보고 쓴 코멘트·편집본을 최신 글에 덮어쓰지 않는다.
  # 버전이 없으면 서버의 현재 버전으로 채우지 않고 거절한다. 첨삭이 완성되지 않은 글(대기·처리 중·실패)도
  # 저장하지 않는다 — 그 화면의 편집 칸은 이전 제출의 첨삭에서 채워진 것이라, 저장하면 새 첨삭이 끝난 뒤
  # student_feedback 이 그 옛 편집본을 우선 노출한다. 확인과 저장은 같은 잠금 안에서 한다.
  def update
    authorize @report, :review?

    outcome = @report.with_lock do
      next :stale unless seen_review_version == @report.review_version
      next :not_ready unless @report.review_ready?

      @report.update(review_params) ? :saved : :invalid
    end

    case outcome
    when :saved
      # 미승인(reviewed false) 편집은 방송하지 않는다(학생 비노출 유지). 승인 후 정정(reviewed true)
      # 은 학생이 이미 볼 수 있는 첨삭이므로 즉시 라이브 반영해 스테일을 막는다.
      @report.broadcast_detail_refresh if @report.reviewed?
      discovered = evaluate_monster_unlocks(@report.user)
      redirect_to teacher_review_path(@report), notice: with_discovery("검토 내용을 저장했어요.", discovered)
    when :invalid
      render :show, status: :unprocessable_entity
    else
      redirect_to teacher_review_path(@report), alert: REJECTION_NOTICES.fetch(outcome)
    end
  end

  # 승인 → reviewed 기록 + 학생 화면 실시간 갱신(P3.9). 교사가 확인한 버전의 완성된 첨삭만(Report#approve!).
  # 인가는 `review?`(담임 권한)로 하고 "완성된 첨삭인가"는 approve! 의 결과로 본다 — `approve?` 로 인가하면
  # 화면을 연 뒤 학생이 다시 내 준비 중이 된 글의 승인이 안내 없는 403 이 된다. 일괄 승인은 `approve?` 로 거른다.
  def approve
    authorize @report, :review?
    # 미제출 초안은 검토 대상이 아니다 — 목록에도 없으니 URL 직접 요청이다(예전 approve? 정책과 같은 403).
    raise Pundit::NotAuthorizedError, "drafts cannot be approved" if @report.draft?

    case @report.approve!(seen_version: seen_review_version)
    when :approved
      discovered = run_approval_effects(@report)
      redirect_to teacher_reviews_path,
                  notice: with_discovery("#{@report.user.name} 학생의 독후감을 승인했어요.", discovered)
    when :already
      # 같은 버전의 재승인(두 번 누름·다른 탭)은 성공한 기존 결과로 안내한다 — 승인 시각·보상·방송은 다시 일으키지 않는다.
      redirect_to teacher_reviews_path, notice: "#{@report.user.name} 학생의 독후감은 이미 승인했어요."
    when :not_ready
      redirect_to teacher_review_path(@report), alert: REJECTION_NOTICES.fetch(:not_ready)
    else
      redirect_to teacher_review_path(@report), alert: REJECTION_NOTICES.fetch(:stale)
    end
  end

  # 선택한 글을 하나씩 검증해 승인하고, **승인한 건수와 제외한 건수를 따로** 알린다 — 준비 중·버전이 바뀐 글·
  # 이미 승인된 글까지 "모두 승인했다"고 말하지 않는다. 폼은 선택한 글마다 화면에 보이던 버전을 함께 보낸다
  # (review_versions[<id>]) — id 목록만으로 현재 버전을 대신 승인하지 않는다. 권한 밖 id 는 스코프에서 빠져
  # 제외 건수에도 세지 않는다(그런 글이 있는지조차 알리지 않는다).
  def batch_approve
    ensure_reviewer!

    versions = params[:review_versions].respond_to?(:to_unsafe_h) ? params[:review_versions].to_unsafe_h : {}
    discovered = []
    approved = skipped = 0
    classroom_scope.where(id: Array(params[:report_ids])).find_each do |report|
      # 정책(approve? = 담임 권한 + 완성된 첨삭)으로 먼저 거르고, 확인한 버전과의 대조·전이는 approve! 가 한다.
      unless ReportPolicy.new(Current.user, report).approve? &&
             report.approve!(seen_version: versions[report.id.to_s]) == :approved
        skipped += 1
        next
      end

      approved += 1
      discovered.concat(run_approval_effects(report))
    end

    redirect_to teacher_reviews_path, notice: with_discovery(batch_notice(approved, skipped), discovered)
  end

  private

  # 교사가 화면에서 확인한 제출 버전(폼의 숨은 칸). 없거나 숫자가 아니면 nil — 어떤 버전과도 같지 않다.
  def seen_review_version
    params[:review_version].to_s[/\A\d{1,9}\z/]&.to_i
  end

  def batch_notice(approved, skipped)
    return "승인한 독후감이 없어요. 첨삭이 준비 중이거나 학생이 다시 낸 글, 이미 승인한 글은 승인하지 않아요." if approved.zero?
    return "독후감 #{approved}편을 승인했어요." if skipped.zero?

    "독후감 #{approved}편을 승인했어요. #{skipped}편은 첨삭이 준비 중이거나 학생이 다시 냈거나 이미 승인한 글이라 승인하지 않았어요."
  end

  # 승인이 **실제로 전이한 뒤**(Report#approve! == :approved, 이미 커밋됨)의 후속 처리: 학생 화면 실시간 갱신 +
  # 승인 시점에 바뀌는 승인-기준 진화/뱃지 조건(reports·a_grades 등) 재계산 + 미션·챌린지 + 몬스터 해금 재평가.
  # 반환: 이번 승인으로 새로 발견한 몬스터(UserMonster) 목록(호출부가 flash 안내에 사용).
  #
  # 여기서 나는 예외로 승인을 되돌리거나 요청을 500 으로 끝내지 않는다 — 승인은 이미 확정됐고, 후속 평가는
  # 모두 멱등이라 다시 평가된다(미션은 Missions::ReevaluateJob, 몬스터 해금은 도감 조회 self-heal, 뱃지는
  # 다음 포인트 변동). 일괄 승인에서 한 글의 후속 실패가 나머지 승인을 막지도 않는다.
  def run_approval_effects(report)
    # 방송·후속 평가는 **지금 DB 의 글**로 한다(§4.4) — 승인 커밋 직후 학생이 다시 냈다면 메모리의 승인된
    # 객체로 그린 목록 행이 "교사 승인 완료"와 이전 제출의 등급을 밀어 넣는다(상세 방송은 모델이 다시 읽는다).
    report.reload
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
  rescue StandardError => e
    Rails.logger.error("Teacher::ReviewsController approval effects failed report=#{report.id}: #{e.class}: #{e.message}")
    []
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

  # 담임 학급의 **제출된** 독후감(검토 상태 무관). 목록 필터·카운트의 기반.
  # `.submitted` 가 여기 있어야 하는 이유: OCR 사진 업로드는 학생이 제출하기 전에 Report 를
  # 영속화하고 OcrJob 이 `ai_status: :done` 을 찍으므로, 이 스코프가 제출 여부를 보지 않으면
  # 미제출 초안이 미검토 큐에 올라온다. 교사가 그걸 승인하면 `reviewed=true` 인데 rubric 은
  # NULL → `feedback_visible?` 영구 false → 5축·첨삭·등급·포인트가 통째로 없는 독후감이 된다.
  def classroom_scope
    Report.submitted.where(classroom_id: Classroom.where(teacher_id: Current.user.id).select(:id))
  end

  # 담임 학급의 미검토 독후감(index 기본 필터). 이미 승인한 글이 승인 캐스케이드를 다시 타지 않게 막는
  # 게이트는 이제 Report#approve! 의 조건부 전이(`reviewed = false` 일 때만)다 — batch_approve 는 학급 경계
  # (classroom_scope)만 걸고 글마다 그 전이 결과를 본다(이미 승인된 글은 제외 건수로 센다).
  def pending_scope
    classroom_scope.where(reviewed: false)
  end

  # 필터별 스코프·정렬. 미검토는 오래 기다린 것 먼저(대기 목록 의미 유지), 검토완료는 최근 승인
  # 먼저(SQLite 는 DESC 에서 NULL 이 뒤로 가므로 레거시 reviewed_at nil 행은 자연히 맨 아래),
  # 전체는 미검토를 위로 올린다.
  def status_scope(status)
    case status
    when "reviewed" then classroom_scope.where(reviewed: true).order(reviewed_at: :desc, created_at: :desc)
    when "all"      then classroom_scope.order(reviewed: :asc, created_at: :asc)
    else                 pending_scope.order(created_at: :asc)
    end
  end

  def ensure_reviewer!
    raise Pundit::NotAuthorizedError unless Current.user.teacher? || Current.user.superadmin?
  end

  # 목록 행도 방송 직전에 다시 읽은 글로 그린다(상세 방송 Report#broadcast_detail_refresh 와 같은 규칙, §4.4).
  def broadcast_to_student(report)
    latest = Report.find_by(id: report.id)
    return unless latest

    latest.broadcast_replace_to(
      [ latest.user, :reports ],
      target: ActionView::RecordIdentifier.dom_id(latest),
      partial: "reports/report",
      locals: { report: latest, show_delete: true }
    )
  end
end
