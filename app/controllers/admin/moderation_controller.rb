# 모더레이션(P7.6). 게시판·토론·토픽의 신고/숨김 상태를 관리한다.
# 숨김 처리 시 hidden_by 를 기록(컬럼이 있는 board_posts). 숨김 콘텐츠는 학생 화면 비노출.
class Admin::ModerationController < Admin::BaseController
  before_action :set_record, only: [ :hide, :unhide ]

  PER_PAGE = 25

  # 게시판·토론글·토픽을 통짜 로드하지 않고 각각 페이지네이션한다(#4).
  # 세 섹션은 독립 page 파라미터(board_page/forum_page/topic_page)로 넘긴다.
  def index
    @board_page, @has_next_board, @board_posts =
      paginate_section(BoardPost.includes(report: :user).order(created_at: :desc), :board_page)
    @forum_page, @has_next_forum, @forum_posts =
      paginate_section(ForumPost.includes(:user, :topic).order(created_at: :desc), :forum_page)
    @topic_page, @has_next_topic, @topics =
      paginate_section(Topic.order(created_at: :desc), :topic_page)
  end

  def hide
    if @record.respond_to?(:hidden_by_id)
      @record.update!(hidden: true, hidden_by: Current.user)
    else
      @record.update!(hidden: true)
    end
    redirect_to admin_moderation_index_path, notice: "콘텐츠를 숨겼어요."
  end

  def unhide
    @record.update!(hidden: false)
    redirect_to admin_moderation_index_path, notice: "숨김을 해제했어요."
  end

  private

  # 관계를 섹션별 page 파라미터로 잘라 [page, has_next?, records] 를 반환한다.
  # 세 섹션이 독립 page 를 가지므로 base 의 paginate(단일 :page) 대신 별도 헬퍼를 쓴다.
  def paginate_section(scope, page_param)
    page = [ params[page_param].to_i, 1 ].max
    records = scope.limit(PER_PAGE + 1).offset((page - 1) * PER_PAGE).to_a
    [ page, records.size > PER_PAGE, records.first(PER_PAGE) ]
  end

  # kind 파라미터로 대상 모델을 정한다: board_post / forum_post / topic.
  def set_record
    @record =
      case params[:kind]
      when "forum_post" then ForumPost.find(params[:id])
      when "topic"      then Topic.find(params[:id])
      else                   BoardPost.find(params[:id])
      end
  end
end
