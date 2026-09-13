class ReportsController < ApplicationController
  before_action :set_report, only: [ :show, :edit, :update, :destroy, :revise, :share ]

  PER_PAGE = 20
  # 자동 저장이 새 글 화면에서 만든 초안을 그 화면 주소로 다시 열어 주는 기간. 새로고침·뒤로 가기·
  # 앱이 화면을 다시 여는 경우만 덮으면 된다 — 며칠 뒤 같은 책으로 새 글을 쓰려는 아이를 옛 초안으로
  # 끌고 가지 않게 짧게 둔다(마지막 저장 기준이라 계속 쓰는 동안은 이어진다).
  AUTOSAVE_ORIGIN_TTL = 2.hours
  # 편집 화면이 여는 순간 만드는 표(Report#autosave_key)의 모양. 브라우저의 UUID(36자) 또는 16진 32자.
  AUTOSAVE_KEY_FORMAT = /\A[\w-]{8,64}\z/

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
    # 같은 편집 화면이 다시 보낸 요청이면(첫 자동 저장이 시간 초과로 끊겨 재시도, 첫 저장을 기다리던
    # 제출) 새로 만들지 않고 그 화면이 이미 만든 초안을 잇는다. 서버는 저장을 마쳤는데 브라우저만
    # 응답을 못 받은 경우 초안이 두 편 생겼다(2차 리뷰 #4). 표는 화면이 열릴 때 만들어 모든 요청에 싣는다.
    existing = report_for_autosave_key
    return continue_report(existing) if existing

    @report = Current.user.reports.new(report_params_with_registered_book)
    @report.classroom = Current.user.classroom
    # 이 화면이 **만든** 글이라는 표(다시 바꾸지 않는다)와, 마지막으로 쓴 화면·순번.
    @report.autosave_key = autosave_key_param
    stamp_autosave_writer(@report)
    @report.autosave_origin_digest = autosave_origin_digest if save_draft?
    link_participation(@report)
    authorize @report

    if save_draft?
      # 임시 저장 — 제출하지 않는다(submitted_at 미기록 → 교사 큐에 안 올라가고 AI 첨삭도 안 돈다).
      # 자동 저장(report-autosave)도 같은 경로를 JSON 으로 부른다. 첫 자동 저장이 초안을 만들고,
      # 그 뒤로는 응답의 update_url 로 같은 초안을 갱신한다.
      return render_draft_invalid(:new) unless draft_body_present?(@report)

      case insert_report
      when :duplicate then continue_report(report_for_autosave_key)
      when true
        respond_to do |format|
          format.html { redirect_to edit_report_path(@report), notice: "임시 저장했어요. 독후감 목록에서 '작성 중'으로 볼 수 있어요." }
          format.json { render_draft_saved(status: :created) }
        end
      else
        render_draft_invalid(:new)
      end
    else
      case insert_report
      when :duplicate then continue_report(report_for_autosave_key)
      when true
        submit_for_review(@report)
        redirect_to @report, notice: "독후감을 제출했어요. 선생님이 확인한 뒤 첨삭 결과를 볼 수 있어요."
      else
        render :new, status: :unprocessable_entity
      end
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

    # 원격 검색으로 고른 책도 여기서 등록한다. 자동 저장이 첫 저장에서 초안을 만든 뒤로는 제출이
    # create 가 아니라 이 update 로 오므로, 여기서 빠지면 첫 저장 뒤에 고른 원격 책은 끝내 연결되지 않는다.
    # 등록은 바깥 검색 API 를 부를 수 있어 잠그기 전에 한다.
    attrs = report_params_with_registered_book

    # 본문 저장과 제출 기록(submitted_at)을 **한 잠금 안에서** 한다. 둘이 따로 커밋되던 때는 그 사이에
    # 끼어든 자동 저장(update_as_draft)이 "아직 초안"을 보고 옛 본문을 써, 선생님께 옛 글이 갔다.
    # AI 첨삭 예약은 잠금(트랜잭션)이 끝난 뒤에 한다 — 커밋 전에 잡이 돌면 제출 전 상태를 읽는다.
    outcome = @report.with_lock do
      # **초안일 때 연 화면**(버전 칸이 있는 폼)은 그사이 제출된 글을 바꾸지 않는다(3차 리뷰 H1). 버전
      # 검사를 초안에만 걸던 때는, 집에서 이미 낸 글을 학교 태블릿의 옛 탭 '제출하기'가 옛 글로 덮고
      # AI 첨삭을 다시 걸었다(승인된 글이면 승인·선생님 편집본까지 풀렸다). 같은 표로 늦게 온 새 글
      # 제출이 이미 낸 글을 다시 내던 것(L2)도 여기서 막힌다 — 새 글 폼의 버전 칸은 빈 값으로 있다.
      next :already_submitted if @report.submitted? && opened_as_draft?
      # 초안을 연 뒤 다른 탭·기기가 더 고쳤으면 이 화면의 글로 덮어 내지 않는다(2차 리뷰 #3 —
      # 자동 저장만 막던 때는 "다른 곳에서 고쳤어요"를 본 아이가 누르는 '제출하기'가 우회로였다).
      next :stale if @report.draft? && stale_draft_version?

      # 판정은 저장 **전** 상태로 한다 — 제출이 곧 submitted_at 을 찍으므로 저장 뒤에는 초안인지 알 수 없다.
      # 잠근 뒤 다시 읽은 값이라 같은 순간 먼저 끝난 요청의 결과를 본다.
      was_draft = @report.draft?
      @report.assign_attributes(attrs)
      # 초안에 쓰면 "마지막으로 쓴 화면"을 이 요청으로 바꾼다 — 담임처럼 표 없이 쓴 저장은 비운다(M2).
      stamp_autosave_writer(@report) if was_draft
      next :invalid unless @report.save

      # 첫 제출을 먼저 본다. 자동 저장된 새 초안을 내면서 본문을 조금 더 고쳤다고 "고쳐 썼어요"라고
      # 안내하면, 고쳐쓰기를 한 적 없는 아이에게 틀린 말이 된다.
      if first_review? && @report.body.present?
        record_submission!(@report)
        :first_submission
      elsif resubmit?(was_draft)
        record_submission!(@report)
        :resubmission
      else
        :saved
      end
    end

    case outcome
    when :already_submitted
      reject_draft_save_after_submit
    when :stale
      reject_stale_draft_save
    when :invalid
      render :edit, status: :unprocessable_entity
    when :first_submission
      AiReviewJob.perform_later(@report)
      redirect_to @report, notice: "독후감을 제출했어요. 선생님이 확인한 뒤 첨삭 결과를 볼 수 있어요."
    when :resubmission
      AiReviewJob.perform_later(@report)
      redirect_to @report, notice: "고쳐 썼어요! 선생님이 다시 확인해요."
    else
      redirect_to @report, notice: "독후감을 저장했어요."
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

  def report_params
    permitted = params.require(:report).permit(:book_id, :book_title, :body, :input_mode, :photo, :drawing, :audio)
    permitted[:book_id] = resolved_book_id(permitted[:book_id]) if permitted.key?(:book_id)
    permitted
  end

  # 제출 시 도서 등록(save 밖 저장 전처리·비차단). book_id 가 비어 있고 검색 버튼으로 고른
  # 원격 책의 remote_isbn 이 있으면 Books::SearchService#register(캐시-우선)로 등록해 book_id 로
  # 링크한다. register 는 raise 하지 않고 nil 로 degrade 하므로(무키·미일치·실패), 실패 시
  # book_id 공란인 채 book_title 폴백으로 저장된다(save 를 막거나 롤백하지 않는다).
  # 정식 카탈로그(recommended) 승격은 여기서 하지 않고 **제출할 때** 한다(record_submission!) —
  # 검색해서 독후감을 낸 책은 실제로 읽힌 책이라 검색·게임·발견에 바로 노출하지만, 자동 저장이 생긴 뒤로는
  # 이 등록이 쓰다 버린 초안에서도 일어난다(2차 리뷰 #12). 초안 동안은 검색 캐시(searched)로 연결만 한다.
  # remote_isbn 은 books/reports 컬럼이 아니므로 permit 하지 않고 params.dig 로만 소비한다.
  def report_params_with_registered_book
    permitted = report_params
    if permitted[:book_id].blank? && (isbn = params.dig(:report, :remote_isbn)).present?
      book = Books::SearchService.new.register(isbn)
      permitted[:book_id] = book.id if book
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
    record_submission!(report)
    AiReviewJob.perform_later(report)
  end

  # 제출 기록(DB 쓰기만). update 는 이것을 본문 저장과 같은 잠금 안에서 부르고, AI 첨삭 예약은
  # 잠금이 끝난 뒤에 따로 한다(submit_for_review 는 둘을 이어 부르는 create 용).
  def record_submission!(report)
    report.update!(ai_status: :pending, reviewed: false, reviewed_at: nil,
                   submitted_at: report.submitted_at || Time.current,
                   teacher_feedback: nil, teacher_rubric: nil, teacher_comment: nil)
    # 승인이 풀리는 지점이므로 공유도 함께 걷는다. 안 걷으면 학생이 승인본을 고쳐 다시 낸 순간
    # **미검토 본문이 게시판에 그대로 공개된 채** 남는다(ReportPolicy#share? 의 승인 게이트를
    # 우회하는 유일한 구멍이었다). 공유 중이 아니면 no-op.
    unshare!(report) if report.shared?
    # 검색으로 고른 책은 낸 순간 정식 카탈로그로 올린다(report_params_with_registered_book 주석). no-op 이면 무해.
    report.book&.promote_from_search!
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
  # · 마지막으로 본 초안일 때만 — 어제 열어 둔 태블릿 탭에 한 글자만 쳐도, 그사이 집에서 더 쓴 본문이
  #   옛 본문으로 통째로 덮였다(2026-09-13 리뷰). 임시 저장 버튼도 같다(2차 리뷰 #3).
  #
  # 저장할 때마다 이 화면의 표와 순번을 "마지막으로 쓴 화면"으로 남긴다(stamp_autosave_writer) — 다음 요청이
  # "마지막으로 쓴 것이 나"인지 알 수 있게(stale_draft_version?).
  #
  # 두 가드는 **잠근 뒤 다시 읽은 상태로 한 번 더** 본다. 잠그기 전의 판정만 믿으면, 읽은 뒤 저장하기
  # 전 사이에 끝난 제출·다른 탭의 저장을 못 보고 그 위에 옛 본문을 쓴다(확인과 갱신 사이의 틈, 리뷰 #11).
  # 제출(update)도 같은 잠금 안에서 본문과 submitted_at 을 함께 쓰므로 둘이 번갈아 끼어들지 않는다.
  def update_as_draft
    raise Pundit::NotAuthorizedError unless @report.user_id == Current.user.id
    # 잠그기 전에 먼저 한 번 본다 — 거절될 요청으로 원격 책을 등록하지 않게.
    return reject_draft_save_after_submit unless @report.draft?
    return reject_stale_draft_save if stale_draft_version?

    attrs = report_params_with_registered_book
    outcome = @report.with_lock do
      next :submitted unless @report.draft?
      next :stale if stale_draft_version?
      next :invalid unless draft_body_present?(@report, incoming: attrs)

      @report.assign_attributes(attrs)
      stamp_autosave_writer(@report)
      @report.save ? :saved : :invalid
    end

    case outcome
    when :submitted then reject_draft_save_after_submit
    when :stale then reject_stale_draft_save
    when :invalid then render_draft_invalid(:edit)
    else
      respond_to do |format|
        format.html { redirect_to edit_report_path(@report), notice: "임시 저장했어요. 이어서 쓸 수 있어요." }
        format.json { render_draft_saved }
      end
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

  # 초안 버전(Report#draft_version)이 지금 것과 다르면 그사이 다른 탭·기기가 이 초안을 더 고친 것이다.
  # 자동 저장(JSON)뿐 아니라 임시 저장 버튼·제출(HTML)도 본다(2차 리뷰 #3). 버전을 싣지 않은 요청
  # (자동 저장이 꺼진 화면)은 예전처럼 받는다.
  #
  # **마지막으로 쓴 것이 이 화면이면 버전이 뒤처져도 받는다**(2차 리뷰 #2). 서버가 저장을 마친 뒤
  # 응답만 끊기면(시간 초과·연결 끊김) 화면의 버전 표는 옛 값이라, 그 재시도를 거절하면 탭 하나만
  # 쓰는데도 "다른 곳에서 고쳤어요"로 멈췄다. 다른 탭·기기(담임 포함)가 사이에 저장했으면 "마지막으로 쓴
  # 화면"이 달라 여전히 거절한다. 같은 화면이라도 **그 저장보다 앞선 순번**의 요청은 거절한다(3차 리뷰
  # M1) — 서버에서 오래 막힌 옛 저장이 재시도 뒤에 처리되거나, 자동 저장이 날아가는 중에 누른 임시 저장이
  # 먼저 처리되면, 늦게 온 옛 요청이 새 글을 되돌렸다. 같은 순번은 응답만 잃고 다시 보낸 같은 내용이라 받는다.
  #
  # **새 글 화면이 만든 초안을 잇는 요청**(continue_report — 첫 저장 재시도·첫 저장을 기다린 제출·동시 첫
  # 저장)은 새 글 폼의 버전 칸이 빈 값이라 버전을 모른다. 그래서 버전 없이 받던 때는, 첫 저장 응답을 잃은
  # 태블릿이 다시 연결되기만 해도 그사이 집에서(또는 담임이) 쓴 더 새 글을 덮었다(4차 리뷰 H-A). 이 경우는
  # "마지막으로 쓴 것이 이 화면이고 앞선 순번이 아닐 때"만 받는다.
  def stale_draft_version?
    sent = params[:draft_version].presence
    return @continuing_from_create ? !same_writer_in_order? : false if sent.nil?
    return false if sent == @report.draft_version

    !same_writer_in_order?
  end

  # 마지막으로 이 초안에 쓴 것이 이 화면이고, 이 요청이 그 저장보다 앞선 순번이 아닌가.
  def same_writer_in_order?
    key = autosave_key_param
    key.present? && key == @report.autosave_writer_key && autosave_seq_param >= @report.autosave_seq.to_i
  end

  # JSON(자동 저장)은 409 로 멈추게 한다. HTML(임시 저장 버튼·제출)은 **이 화면에서 쓴 글을 그대로 둔 채**
  # 편집 화면을 다시 그린다 — 버전 표에는 서버의 최신 값이 실리므로, 아이가 버튼을 한 번 더 누르면 이
  # 화면의 글로 바꾸겠다는 뜻이 된다. 최신 글을 보려면 편집 화면을 새로 연다(안내 배너에 링크).
  # 이 화면에서는 자동 저장을 끈다 — 입력만으로 다른 곳의 글을 덮지 않게(_form 의 conflict).
  def reject_stale_draft_save
    respond_to do |format|
      # edit_url — 새 글 화면에서 멈췄으면 브라우저가 주소만 이 초안으로 바꿔, 새로 고치면 최신 글이 열리게.
      format.json { render json: { error: "stale", edit_url: edit_report_path(@report) }, status: :conflict }
      format.html do
        @report.assign_attributes(report_params)
        @draft_conflict = true
        render :edit, status: :conflict
      end
    end
  end

  # 모든 폼 요청이 싣는 이 편집 화면의 표(report-autosave 가 화면을 열 때 만든다). 모양이 틀리면 없는 것으로 본다.
  def autosave_key_param
    params[:autosave_key].to_s[AUTOSAVE_KEY_FORMAT]
  end

  # 이 화면 안에서 요청을 보낸 순번(브라우저의 입력 횟수, 단조 증가). 모양이 틀리면 0.
  def autosave_seq_param
    params[:autosave_seq].to_s[/\A\d{1,9}\z/].to_i
  end

  # 이 요청을 보낸 화면을 "마지막으로 쓴 화면"으로 남긴다(순번 포함). 표 없이 온 저장(담임·스크립트 없는
  # 화면)은 비운다 — 그래야 학생 옛 탭이 "마지막으로 쓴 것이 나"라며 그 저장을 덮지 못한다(3차 리뷰 M2).
  def stamp_autosave_writer(report)
    key = autosave_key_param
    report.autosave_writer_key = key
    report.autosave_seq = key && autosave_seq_param
  end

  # 새 글 저장. 같은 화면 표의 첫 저장 두 개가 동시에 들어와 한쪽이 먼저 만들었으면(유일 인덱스가 둘째를
  # 막는다) :duplicate 를 돌려준다 — 부른 쪽이 그 초안을 잇는다. 이 표가 아닌 유일 위반은 그대로 올린다
  # (예외 처리를 create 전체에 두면 나중에 생길 다른 유일 조건 위반까지 조용히 이어 쓰기로 흘러간다 — L4).
  def insert_report
    @report.save
  rescue ActiveRecord::RecordNotUnique => e
    raise e unless e.message.include?("reports.autosave_key") && report_for_autosave_key

    :duplicate
  end

  # 같은 화면이 **만든** 글(첫 저장 재시도·첫 저장을 기다린 제출). "마지막으로 쓴 화면"이 아니라 만든
  # 화면으로 찾는다 — 그사이 다른 탭이 그 초안을 저장해도 첫 화면의 재시도가 제 초안을 찾는다(L1).
  def report_for_autosave_key
    key = autosave_key_param
    key && Current.user.reports.find_by(autosave_key: key)
  end

  # create 로 온 요청을 이미 있는 글의 update 로 처리한다(인가·버전·잠금·제출 판정이 모두 update 에 있다).
  # 새 글 화면의 버전 칸은 비어 있으므로 stale_draft_version? 이 이 표시를 보고 화면·순번으로 판단한다.
  def continue_report(report)
    @report = report
    @continuing_from_create = true
    update
  end

  # 자동 저장의 첫 create 가 실어 온 새 글 화면 주소(/reports/new?…)의 지문. 새 글 화면 주소가 아니면
  # 기억하지 않는다. 원문이 아니라 지문을 초안 행에 둔다 — 단계 학습은 본문 전체를 주소에 실어 넘겨,
  # 원문을 세션 쿠키에 넣던 때는 쿠키 한도(4KB)를 넘어 첫 저장이 500 으로 끝나고 재시도마다 초안이
  # 늘었다(2차 리뷰 #1). 쿠키에 두면 동시에 나간 다른 요청이 옛 쿠키를 되써 기억이 사라지기도 했다(#11).
  def autosave_origin_digest
    origin = params[:autosave_origin].to_s
    return unless origin == new_report_path || origin.start_with?("#{new_report_path}?")

    Digest::SHA256.hexdigest(origin)
  end

  # 이 새 글 화면에서 자동 저장이 만든, 아직 내지 않은 최근 초안. 낸 글·지운 글, 마지막 저장에서
  # AUTOSAVE_ORIGIN_TTL 이 지난 초안은 대상이 아니다 — 다음 새 글은 정말 새 글이다.
  def autosaved_draft_from_here
    Current.user.reports.where(submitted_at: nil, autosave_origin_digest: Digest::SHA256.hexdigest(request.fullpath))
           .where(updated_at: AUTOSAVE_ORIGIN_TTL.ago..).order(updated_at: :desc).first
  end

  def render_draft_invalid(template)
    respond_to do |format|
      format.html { render template, status: :unprocessable_entity }
      format.json { render json: { errors: @report.errors.full_messages }, status: :unprocessable_entity }
    end
  end

  # 초안일 때 연 화면에서 온 저장·제출인데 그사이 글이 제출됐다(다른 탭·기기에서 냈다). JSON(자동 저장)은
  # 409 로 멈추게 하고, HTML(임시 저장 버튼·제출)은 **이 화면에서 쓴 글을 그대로 보여 주는** 편집 화면을
  # 다시 그린다 — 예전처럼 글 화면으로 보내면 방금 쓴 글이 사라졌다. 이 화면에는 저장·제출 버튼이 없다
  # (이미 낸 글을 이 화면의 글로 바꾸는 길을 두지 않는다 — 더 고치려면 글 화면의 '고쳐쓰기').
  def reject_draft_save_after_submit
    respond_to do |format|
      format.json { render json: { error: "already_submitted" }, status: :conflict }
      format.html do
        @report.assign_attributes(report_params)
        @submitted_conflict = true
        render :edit, status: :conflict
      end
    end
  end

  # 초안일 때 연 폼에서 온 요청인가. 초안 폼에는 모두 `opened_as_draft` 표시가 있다(_form). 버전 칸만 보던
  # 때는 버전 칸이 없는 **사진 첫 제출 화면**이 빠져, 집에서 내고 승인까지 받은 글을 그 화면의 '제출하기'가
  # 판독 원문으로 덮고 승인을 풀었다(4차 리뷰 H-B). 표시가 생기기 전에 연 화면을 위해 버전 칸도 본다.
  def opened_as_draft?
    params[:opened_as_draft].present? || params.key?(:draft_version)
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
