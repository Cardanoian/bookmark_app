# 모더레이션(P7.6). 게시판·토론·토픽의 신고/숨김 상태를 관리한다.
# 숨김 처리 시 hidden_by 를 기록(컬럼이 있는 board_posts). 숨김 콘텐츠는 학생 화면 비노출.
class Admin::ModerationController < Admin::BaseController
  before_action :set_record, only: [ :hide, :unhide ]

  def index
    @board_posts = BoardPost.includes(report: :user).order(created_at: :desc)
    @forum_posts = ForumPost.includes(:user, :topic).order(created_at: :desc)
    @topics = Topic.order(created_at: :desc)
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
