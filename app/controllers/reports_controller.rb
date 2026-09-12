class ReportsController < ApplicationController
  before_action :set_report, only: [ :show, :edit, :update, :destroy, :revise, :share ]

  PER_PAGE = 20
  # 자동 저장이 새 글 화면에서 만든 초안을 그 화면 주소로 다시 열어 주는 기간. 새로고침·뒤로 가기·
  # 앱이 화면을 다시 여는 경우만 덮으면 된다 — 며칠 뒤 같은 책으로 새 글을 쓰려는 아이를 옛 초안으로
  # 끌고 가지 않게 짧게 둔다(마지막 저장 기준이라 계속 쓰는 동안은 이어진다).
  AUTOSAVE_ORIGIN_TTL = 2.hours

  # 학생은 자기 글, 교사는 담당 학급 글(정책 스코프). 무제한 목록을 페이지네이션한다.
  # 필터(book_id/book_title/reviewed)는 반드시 policy_scope 위에만 얹어 위조 파라미터로 남의 글이
  # 노출되지 않게 한다. book_title 은 레거시(book_id nil) 독후감 조회용이며 squish 로 정규화한다.
  def index
    authorize Report
    @page = [ params[:page].to_i, 1 ].max
    records = policy_scope(Report).includes(:book, :user)
    # book_id(정식 도서)와 book_title(레거시 도서 미연결)은 상호배타 진입점이므로 함께 오면
    # book_id 를 우선한다(둘을 AND 로 걸면 book_id=X AND book_id IS NULL 모순으로 항상 빈 결과).
    if params[:book_id].present?
      records = records.where(book_id: params[:book_id])
    elsif params[:book_title].present?
      records = records.where(book_id: nil, book_title: params[:book_title].to_s.squish)
    end
    records = records.where(reviewed: true) if params[:reviewed] == "true"
    records = records.order(created_at: :desc)
                .limit(PER_PAGE + 1).offset((@page - 1) * PER_PAGE).to_a
    @has_next_page = records.size > PER_PAGE
    @reports = records.first(PER_PAGE)

    @book = Book.find_by(id: params[:book_id]) if params[:book_id].present?
    @reviewed_filter = params[:reviewed] == "true"
    @book_title_filter = params[:book_title].to_s.squish.presence
  end

  def show
    authorize @report
  end

  def new
    @guided = ReadingDomain.guided_questions(ReadingDomain.guided_band_for(Current.user.classroom&.grade))
    @report = Current.user.reports.new(prefill_attributes)
    authorize @report

    # 이 새 글 화면에서 자동 저장이 이미 초안을 만들었으면(새로고침·뒤로 가기·앱이 화면을 다시 엶)
    # 빈 새 글 대신 그 초안을 연다. 안 그러면 아이가 빈 폼에 다시 쓰며 '작성 중' 글이 두 편 생긴다.
    # 앱은 자동 저장이 바꾼 주소(history.replace)를 모르고 처음 주소로 화면을 다시 연다.
    draft = autosaved_draft_from_here
    redirect_to edit_report_path(draft), notice: "쓰던 글을 이어서 열었어요." if draft
  end

  def create
    @report = Current.user.reports.new(report_params_with_registered_book)
    @report.classroom = Current.user.classroom
    link_participation(@report)
    authorize @report

    if save_draft?
      # 임시 저장 — 제출하지 않는다(submitted_at 미기록 → 교사 큐에 안 올라가고 AI 첨삭도 안 돈다).
      # 자동 저장(report-autosave)도 같은 경로를 JSON 으로 부른다. 첫 자동 저장이 초안을 만들고,
      # 그 뒤로는 응답의 update_url 로 같은 초안을 갱신한다.
      return render_draft_invalid(:new) unless draft_body_present?(@report)

      if @report.save
        respond_to do |format|
          format.html { redirect_to edit_report_path(@report), notice: "임시 저장했어요. 독후감 목록에서 '작성 중'으로 볼 수 있어요." }
          format.json do
            remember_autosave_origin(@report)
            render_draft_saved(status: :created)
          end
        end
      else
        render_draft_invalid(:new)
      end
    elsif @report.save
      submit_for_review(@report)
      redirect_to @report, notice: "독후감을 제출했어요. 선생님이 확인한 뒤 첨삭 결과를 볼 수 있어요."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @report
  end

  def update
    authorize @report

    # 임시 저장은 **제출 판정을 통째로 건너뛴다.** resubmit? 뿐 아니라 first_review? 도 반드시
    # 우회해야 한다 — 미제출 초안은 rubric 이 비어 있어 first_review? 가 참이므로, 안 건너뛰면
    # "임시 저장" 버튼이 곧 "제출하기"가 되어 AI 첨삭이 돌고 교사 큐에 올라간다.
    return update_as_draft if save_draft?

    # 판정은 저장 **전** 상태로 한다 — 제출이 곧 submitted_at 을 찍으므로 저장 뒤에는 초안인지 알 수 없다.
    was_draft = @report.draft?

    # 원격 검색으로 고른 책도 여기서 등록한다. 자동 저장이 첫 저장에서 초안을 만든 뒤로는 제출이
    # create 가 아니라 이 update 로 오므로, 여기서 빠지면 첫 저장 뒤에 고른 원격 책은 끝내 연결되지 않는다.
    if @report.update(report_params_with_registered_book)
      # 첫 제출을 먼저 본다. 자동 저장된 새 초안을 내면서 본문을 조금 더 고쳤다고 "고쳐 썼어요"라고
      # 안내하면, 고쳐쓰기를 한 적 없는 아이에게 틀린 말이 된다.
      if first_review? && @report.body.present?
        submit_for_review(@report)
        redirect_to @report, notice: "독후감을 제출했어요. 선생님이 확인한 뒤 첨삭 결과를 볼 수 있어요."
      elsif resubmit?(was_draft)
        submit_for_review(@report)
        redirect_to @report, notice: "고쳐 썼어요! 선생님이 다시 확인해요."
      else
        redirect_to @report, notice: "독후감을 저장했어요."
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @report
    @report.destroy!

    redirect_to reports_path, notice: "독후감을 삭제했어요.", status: :see_other
  end

  # 고쳐쓰기: 원본을 잇는 새 독후감을 만든다(P3.10).
  # 본문이 원본과 동일한 초기 상태에서는 재첨삭을 예약하지 않는다(#misc: 동일 본문 AI 재호출 낭비).
  # 대신 원본의 첨삭 결과를 이어받아 done 으로 시작하고, 학생이 본문을 고쳐 저장하면
  # update 의 resubmit? 가드(본문 변경 시에만)가 실제 재첨삭을 예약한다.
  def revise
    authorize @report, :revise?

    revision = Current.user.reports.new(
      classroom: @report.classroom,
      book_id: @report.book_id,
      book_title: @report.book_title,
      body: @report.body,
      input_mode: @report.input_mode,
      revision_of: @report,
      prev_avg: @report.avg,
      rubric: @report.rubric,
      avg: @report.avg,
      level: @report.level,
      ai_status: :done
    )

    if revision.save
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
      unshare!(@report)
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

  # 새 독후감 기본값 + 위저드(P5.5)·책 선택 스텝 초안 프리필(book_id/book_title/body).
  # book_id 는 표시(표지·@report.book)용으로만 프리필하며, 위조·스테일 id 는 @report.book 이
  # nil 이라 표시에만 영향을 준다. 실제 저장 시 book_id 는 report_params 의 resolved_book_id 가
  # 재검증하므로 무효 참조는 저장되지 않는다.
  def prefill_attributes
    attrs = { input_mode: params[:input_mode].presence || "keyboard" }
    attrs.merge!(params.require(:report).permit(:book_id, :book_title, :body).to_h) if params[:report].present?
    attrs
  end

  # 챌린지 참여 후 첫 작성 글에 challenge_id 를 연결한다. 참여 플래그는 세션에서 소비(1회성).
  # [menu_refactor 심화 PR6] 미션 분기는 제거했다 — 미션은 세션 참여가 아니라 발행 시 자동 배정되고
  # 승인·게임 이벤트로 자동 진행되므로 reports.mission_id 연결이 필요 없다(챌린지 분기만 유지).
  def link_participation(report)
    if (challenge_id = session.delete(:active_challenge_id))
      report.challenge_id = challenge_id if Challenge.exists?(id: challenge_id)
    end
  end

  def report_params
    permitted = params.require(:report).permit(:book_id, :book_title, :body, :input_mode, :photo, :drawing, :audio)
    permitted[:book_id] = resolved_book_id(permitted[:book_id]) if permitted.key?(:book_id)
    permitted
  end

  # 제출 시 도서 등록(save 밖 저장 전처리·비차단). book_id 가 비어 있고 검색 버튼으로 고른
  # 원격 책의 remote_isbn 이 있으면 Books::SearchService#register(캐시-우선)로 등록해 book_id 로
  # 링크한다. register 는 raise 하지 않고 nil 로 degrade 하므로(무키·미일치·실패), 실패 시
  # book_id 공란인 채 book_title 폴백으로 저장된다(save 를 막거나 롤백하지 않는다).
  # 등록된 책은 `promote_from_search!`로 정식 카탈로그(recommended)로 즉시 승격한다 — 검색해서
  # 독후감을 쓴 책은 일회성 캐시가 아니라 실제로 읽힌 책이므로 검색·게임·발견에 바로 노출한다.
  # remote_isbn 은 books/reports 컬럼이 아니므로 permit 하지 않고 params.dig 로만 소비한다.
  def report_params_with_registered_book
    permitted = report_params
    if permitted[:book_id].blank? && (isbn = params.dig(:report, :remote_isbn)).present?
      book = Books::SearchService.new.register(isbn)
      if book
        book.promote_from_search!
        permitted[:book_id] = book.id
      end
    end
    permitted
  end

  # 자동완성이 채운 book_id 를 검증한다(WS-D). 공백 문자열은 nil, 실존하지 않는 Book id 도 nil 로
  # 무시해 book_title 자유텍스트 폴백으로 저장되게 한다(위조·스테일 id 로 인한 무효 참조 차단).
  def resolved_book_id(raw)
    id = raw.presence
    return nil if id.nil?

    Book.exists?(id) ? id : nil
  end

  # 제출/재제출: 검토 상태를 완전히 리셋(미검토로 되돌리고 교사 편집본 클리어)한 뒤 AiReviewJob 을 예약한다.
  # 승인본(reviewed=true)을 학생이 직접 편집·재제출하면 reviewed 를 false 로 되돌려 첨삭 비공개 게이트
  # (feedback_visible?)에 재진입시키고, 담임 재검토 목록(pending_scope, reviewed:false)으로 복귀시킨다.
  # 본문이 바뀌어 새 AI 첨삭이 생성되므로, 옛 본문을 대상으로 한 교사 편집본
  # (teacher_feedback/teacher_rubric/teacher_comment)은 스테일이라 함께 클리어한다
  # (클리어하지 않으면 재승인 후 student_feedback 이 스테일 teacher_feedback 을 우선 노출하는 2차 버그).
  # create(신규)·OCR 초안·revise(새 레코드)는 이미 reviewed=false·교사필드 nil 이라 no-op(무해).
  #
  # `submitted_at` 은 **여기가 유일한 기록 지점**이다. OCR 초안은 사진 업로드 시점에 이미 영속화
  # 되므로(OcrController#create) "레코드가 있다 = 제출했다"가 성립하지 않는다. 제출 사실을
  # ai_status 로 추론하면 OcrJob 이 찍은 done 이 첨삭 완료로 오인돼 교사 큐에 초안이 새고,
  # 그대로 승인되면 rubric 없는 독후감이 확정된다(Report#submitted? 주석 참조).
  # 재제출은 시각을 갱신하지 않는다 — 술어(`submitted?`)에는 갱신이 불필요하고, 덮어쓰면
  # "언제 처음 냈는가"라는 되살릴 수 없는 사실만 잃는다.
  def submit_for_review(report)
    report.update!(ai_status: :pending, reviewed: false, reviewed_at: nil,
                   submitted_at: report.submitted_at || Time.current,
                   teacher_feedback: nil, teacher_rubric: nil, teacher_comment: nil)
    # 승인이 풀리는 지점이므로 공유도 함께 걷는다. 안 걷으면 학생이 승인본을 고쳐 다시 낸 순간
    # **미검토 본문이 게시판에 그대로 공개된 채** 남는다(ReportPolicy#share? 의 승인 게이트를
    # 우회하는 유일한 구멍이었다). 공유 중이 아니면 no-op.
    unshare!(report) if report.shared?
    AiReviewJob.perform_later(report)
  end

  # 공유 해제 + 게시물 파기. share 액션의 취소 분기와 submit_for_review 가 공용한다.
  # board_post 파기 → 응원(cheers)이 cascade 삭제된다. 스티커는 report 소속이라 유지.
  # cheers_count 는 콜백 없는 수동 카운터라 여기서 0 으로 초기화해야 재공유·스탯 집계가
  # 어긋나지 않는다(ReadingStats#cheers_received 과대 집계 방지).
  def unshare!(report)
    report.board_post&.destroy
    report.update!(shared: false, cheers_count: 0)
  end

  # "임시 저장" 버튼(name="save_draft")으로 들어온 요청인지. 제출 버튼과 같은 폼을 쓰되 이름으로만
  # 갈린다 — 별도 라우트를 만들지 않아 폼·인가 계약이 하나로 유지된다.
  def save_draft?
    params[:save_draft].present?
  end

  # 초안 저장(제출 아님). 본문 변경만 반영하고 submitted_at·ai_status 는 건드리지 않는다.
  #
  # 세 가드는 자동 저장이 생기면서 필요해졌다.
  # · 작성자 본인만 — 초안은 아이의 쓰는 중인 글이다. 정책은 담임의 update 도 허용하지만,
  #   임시 저장·자동 저장은 작성 학생에게만 켠다(_form).
  # · 아직 내지 않은 글만 — 다른 탭에서 방금 제출한 글을 남은 탭의 자동 저장이 덮어쓰면,
  #   교사가 보는 본문과 AI 첨삭 대상이 어긋난다. 제출된 글의 본문은 제출 경로로만 바뀐다.
  # · 자동 저장은 마지막으로 본 초안일 때만 — 어제 열어 둔 태블릿 탭에 한 글자만 쳐도, 그사이 집에서
  #   더 쓴 본문이 옛 본문으로 통째로 덮였다(2026-09-13 리뷰).
  def update_as_draft
    raise Pundit::NotAuthorizedError unless @report.user_id == Current.user.id
    return reject_draft_save_after_submit unless @report.draft?
    return reject_stale_draft_save if stale_draft_version?

    attrs = report_params_with_registered_book
    if !draft_body_present?(@report, incoming: attrs)
      render_draft_invalid(:edit)
    elsif @report.update(attrs)
      respond_to do |format|
        format.html { redirect_to edit_report_path(@report), notice: "임시 저장했어요. 이어서 쓸 수 있어요." }
        format.json { render_draft_saved }
      end
    else
      render_draft_invalid(:edit)
    end
  end

  # 자동 저장 응답. 폼이 다음 저장부터 같은 초안을 갱신하도록 update_url 을, 새로고침해도 이어
  # 쓰도록 edit_url 을 준다. book_id 는 원격 검색으로 고른 책이 저장하며 등록된 경우를 위한
  # 것이다 — 폼의 숨은 book_id 는 비어 있으므로, 이 값을 심지 않으면 다음 저장이 연결을 끊는다.
  # draft_version 은 다음 저장이 "내가 본 초안이 아직 최신인가"를 묻는 표다(stale_draft_version?).
  def render_draft_saved(status: :ok)
    render json: { id: @report.id,
                   update_url: report_path(@report),
                   edit_url: edit_report_path(@report),
                   book_id: @report.book_id,
                   draft_version: @report.draft_version,
                   saved_at: @report.updated_at.iso8601 }, status: status
  end

  # 자동 저장(JSON)이 보낸 초안 버전이 지금 것과 다르면 그사이 다른 탭·기기가 이 초안을 더 고친 것이다.
  # 임시 저장 버튼·제출(HTML)은 보지 않는다 — 아이가 지금 화면의 글로 하겠다고 직접 누른 것이라서다.
  # 버전을 싣지 않은 요청(자동 저장 도입 전 스크립트가 남은 화면)은 예전처럼 받는다.
  def stale_draft_version?
    request.format.json? && params[:draft_version].present? && params[:draft_version] != @report.draft_version
  end

  def reject_stale_draft_save
    render json: { error: "stale" }, status: :conflict
  end

  # 자동 저장이 새 글 화면(/reports/new?…)에서 초안을 만들었다 — 그 화면 주소를 기억해 new 가 같은
  # 주소로 다시 오면 초안을 열어 준다(autosaved_draft_from_here). 주소는 브라우저가 연결된 순간의
  # 것을 싣는다(떠나는 순간에 저장하면 location 이 이미 다음 화면이다). 하나만 기억해 쿠키를 키우지 않는다.
  def remember_autosave_origin(report)
    origin = params[:autosave_origin].to_s
    return unless origin == new_report_path || origin.start_with?("#{new_report_path}?")

    session[:autosave_origin] = { "path" => origin, "report_id" => report.id }
  end

  def autosaved_draft_from_here
    memo = session[:autosave_origin]
    return unless memo.is_a?(Hash) && memo["path"] == request.fullpath

    draft = Current.user.reports.find_by(id: memo["report_id"])
    return draft if draft&.draft? && draft.updated_at >= AUTOSAVE_ORIGIN_TTL.ago

    # 이미 냈거나 지웠거나 오래된 초안이면 잊는다 — 다음 새 글은 정말 새 글이다.
    session.delete(:autosave_origin)
    nil
  end

  def render_draft_invalid(template)
    respond_to do |format|
      format.html { render template, status: :unprocessable_entity }
      format.json { render json: { errors: @report.errors.full_messages }, status: :unprocessable_entity }
    end
  end

  def reject_draft_save_after_submit
    respond_to do |format|
      format.html { redirect_to @report, alert: "이미 제출한 글이라 임시 저장할 수 없어요." }
      format.json { render json: { error: "already_submitted" }, status: :conflict }
    end
  end

  # 빈 초안은 만들지 않는다. Report 에는 body presence 검증이 없어(사진 초안은 본문 없이 태어난다)
  # 이 가드가 없으면 아무것도 안 쓰고 누른 "임시 저장"이 빈 '작성 중' 글을 목록에 쌓는다.
  # 본문 칸을 싣지 않은 요청(책만 바꾼 저장)은 저장된 본문을 본다 — 없는 칸을 빈 본문으로 읽지 않는다.
  def draft_body_present?(report, incoming: nil)
    body = incoming&.key?(:body) ? incoming[:body] : report.body
    return true if body.present?

    report.errors.add(:body, "를 조금이라도 쓴 뒤에 임시 저장할 수 있어요.")
    false
  end

  # 작성자가 실제로 고친 글을 낸 경우에만 재첨삭.
  #
  # **고쳐쓰기 초안은 "이번 요청에서 본문이 바뀌었나"로 판정하면 안 된다.** 자동 저장이 본문을
  # 미리 저장해 두므로 '수정하기'를 누르는 요청 자체에는 본문 변경이 없을 수 있고, 그러면 고쳐 쓴
  # 글이 선생님께 영영 가지 않는다. 그래서 초안이면 원본(revision_of) 본문과 비교한다 — 원본과
  # 같으면 여전히 재첨삭을 건너뛴다(revise 의 "동일 본문 AI 재호출 낭비" 방지 유지).
  # 이미 낸 글을 다시 고친 경우만 이번 요청의 변경을 본다.
  def resubmit?(was_draft)
    return false unless Current.user.id == @report.user_id
    return @report.saved_change_to_body? unless was_draft && @report.revision?

    normalized_body(@report.body) != normalized_body(@report.revision_of&.body)
  end

  # 브라우저는 textarea 줄바꿈을 CRLF 로 보낸다. 앞뒤 공백·줄바꿈 차이만으로 "고쳤다"고 보지 않는다.
  def normalized_body(text)
    text.to_s.gsub(/\r\n?/, "\n").strip
  end

  # 본인 글의 첫 제출인지(Report#first_submission? — 첨삭 받은 적 없는 글, 원본을 지운 고쳐쓰기 초안).
  # 원본이 있는 revise 초안은 제외되므로 "동일 본문 재첨삭 스킵"이 유지된다.
  # update 는 submitted_at 을 건드리지 않으므로 저장 뒤에 불러도 draft? 는 저장 전과 같다.
  def first_review?
    Current.user.id == @report.user_id && @report.first_submission?
  end
end
