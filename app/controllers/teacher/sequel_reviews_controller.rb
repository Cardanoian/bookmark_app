# 뒷이야기 코멘트 검토(2026-09-19). 책갈피 도우미(AI)가 학생 뒷이야기에 단 격려 코멘트를 **담임이 읽고**
# (필요하면 고쳐) 승인해야 작성 학생에게 보인다 — 독후감 첨삭의 검토·승인과 같은 규칙이다.
# 경계는 뒷이야기의 학급(sequel.classroom — 또래 열람 경계와 같다)이며 `owned_classroom!` 이 403 으로 막는다.
# 승인은 코멘트 한 칸을 담은 폼 하나라(수정과 승인이 같은 요청) quiz_contributions 의 형제 폼 문제가 없다.
class Teacher::SequelReviewsController < Teacher::BaseController
  PER_PAGE = 20
  STATUS_FILTERS = %w[pending reviewed].freeze

  def index
    load_index
    # 마지막 쪽의 마지막 글을 승인하면 빈 쪽으로 돌아온다. 앞쪽에 글이 남아 있으면 그리로 보낸다.
    if @sequels.empty? && @page > 1
      redirect_to teacher_sequel_reviews_path(status: @status, page: (@page - 1 if @page > 2))
    end
  end

  # 승인(또는 승인한 코멘트 다시 고치기). 폼의 코멘트가 최종본이다.
  def approve
    @sequel = BookSequel.find(params[:id])
    owned_classroom!(@sequel.classroom)

    # 잠근 채 다시 읽고 판단한다 — 확인과 저장 사이에 코멘트 잡이 processing 으로 넘어가 ai_comment 를
    # 바꾸면 담임이 읽지 않은 코멘트가 승인된다(잡 쪽은 reviewed_at 이 빈 글만 조건부로 잡는다).
    was_reviewed = false
    outcome = @sequel.with_lock do
      next :busy unless @sequel.reviewable?

      was_reviewed = @sequel.reviewed?
      @sequel.approve(by: Current.user, comment: comment_param) ? :approved : :invalid
    end

    case outcome
    when :busy
      redirect_to teacher_sequel_reviews_path(back_params),
                  alert: "책갈피 도우미가 아직 코멘트를 쓰고 있어요. 잠시 뒤에 다시 확인해 주세요."
    when :approved
      @sequel.broadcast_feedback_refresh
      redirect_to teacher_sequel_reviews_path(back_params),
                  notice: was_reviewed ? "코멘트를 고쳤어요. 학생 화면에 바로 반영돼요." : "승인했어요. 이제 학생이 코멘트를 볼 수 있어요."
    else
      load_index
      render :index, status: :unprocessable_entity
    end
  end

  private

  def load_index
    @status = normalized_status
    @page = [ params[:page].to_i, 1 ].max

    classroom_scope = BookSequel.where(classroom_id: teacher_classrooms.select(:id))
    @pending_count = classroom_scope.awaiting_review.count
    @reviewed_count = classroom_scope.reviewed.count

    scoped = if @status == "reviewed"
      classroom_scope.reviewed.order(reviewed_at: :desc, created_at: :desc)
    else
      classroom_scope.awaiting_review.order(:created_at) # 오래 기다린 글 먼저
    end
    rows = scoped.includes(:user, :book).offset((@page - 1) * PER_PAGE).limit(PER_PAGE + 1).to_a
    @has_next_page = rows.size > PER_PAGE
    @sequels = rows.first(PER_PAGE)
  end

  # 미지정·위조값은 pending(교사의 할 일 목록 — reviews_controller 관례).
  def normalized_status
    STATUS_FILTERS.include?(params[:status]) ? params[:status] : "pending"
  end

  # 폼의 코멘트. book_sequel 이 해시가 아닌 위조 요청(`book_sequel=abc`)도 500 이 아니라 빈 코멘트(422)로
  # 끝나게 한다. 배열 같은 비스칼라 값도 permit 이 걸러 빈 코멘트가 된다.
  def comment_param
    attrs = params[:book_sequel]
    attrs.respond_to?(:permit) ? attrs.permit(:comment)[:comment] : nil
  end

  # 승인 뒤 같은 탭·페이지로 돌아간다(검토완료 탭에서 고친 교사가 미검토 탭으로 튕기지 않게).
  def back_params
    { status: normalized_status, page: params[:page].presence }.compact
  end
end
