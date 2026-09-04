class ReportsController < ApplicationController
  before_action :set_report, only: [ :show, :edit, :update, :destroy, :revise, :share ]

  PER_PAGE = 20

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
  end

  def create
    @report = Current.user.reports.new(report_params_with_registered_book)
    @report.classroom = Current.user.classroom
    link_participation(@report)
    authorize @report

    if save_draft?
      # 임시 저장 — 제출하지 않는다(submitted_at 미기록 → 교사 큐에 안 올라가고 AI 첨삭도 안 돈다).
      return render :new, status: :unprocessable_entity unless draft_body_present?(@report)

      if @report.save
        redirect_to edit_report_path(@report), notice: "임시 저장했어요. 독후감 목록에서 '작성 중'으로 볼 수 있어요."
      else
        render :new, status: :unprocessable_entity
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

    if @report.update(report_params)
      if resubmit?
        submit_for_review(@report)
        redirect_to @report, notice: "고쳐 썼어요! 선생님이 다시 확인해요."
      elsif first_review? && @report.body.present?
        submit_for_review(@report)
        redirect_to @report, notice: "독후감을 제출했어요. 선생님이 확인한 뒤 첨삭 결과를 볼 수 있어요."
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
  def update_as_draft
    if !draft_body_present?(@report, incoming: report_params)
      render :edit, status: :unprocessable_entity
    elsif @report.update(report_params)
      redirect_to edit_report_path(@report), notice: "임시 저장했어요. 이어서 쓸 수 있어요."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # 빈 초안은 만들지 않는다. Report 에는 body presence 검증이 없어(사진 초안은 본문 없이 태어난다)
  # 이 가드가 없으면 아무것도 안 쓰고 누른 "임시 저장"이 빈 '작성 중' 글을 목록에 쌓는다.
  def draft_body_present?(report, incoming: nil)
    body = incoming ? incoming[:body] : report.body
    return true if body.present?

    report.errors.add(:body, "를 조금이라도 쓴 뒤에 임시 저장할 수 있어요.")
    false
  end

  # 작성자가 본문을 바꿔 다시 낸 경우에만 재첨삭.
  def resubmit?
    Current.user.id == @report.user_id && @report.saved_change_to_body?
  end

  # 아직 AI 첨삭 이력이 없고(고쳐쓰기 아님) 본인 글이면 첫 제출로 간주(OCR 초안 등).
  # revise 초안은 revision_of_id 가 있어 제외되므로 "동일 본문 재첨삭 스킵"이 유지된다.
  # rubric 은 JSON 컬럼이라 nil·빈해시 모두 blank? true(미첨삭 판정).
  def first_review?
    Current.user.id == @report.user_id && @report.revision_of_id.nil? && @report.rubric.blank?
  end
end
