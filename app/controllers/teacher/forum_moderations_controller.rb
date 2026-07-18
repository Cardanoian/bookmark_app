# 교사 토론 모더레이션(reading_discussion). 담임이 **자기 학급 학생이 쓴** 토론 글을 숨기거나
# 다시 보이게 한다. 경계는 저자 학급 소유(owned_student! — student.classroom.teacher_id == 교사)로
# 강제하므로, 학교-스코프 토픽에서 타 학급 학생이 쓴 글은 담임이 아니라 403 이다(신고 라우팅과 정합).
# 자동 숨김이 없는 대신 이 수동 경로 + 총괄 Admin::Moderation 이 실제 숨김을 담당한다.
class Teacher::ForumModerationsController < Teacher::BaseController
  before_action :require_reading_discussion!
  before_action :set_forum_post

  def hide
    owned_student!(@forum_post.user)
    @forum_post.update!(hidden: true, hidden_by: Current.user)
    redirect_back fallback_location: teacher_dashboard_path, notice: "토론 글을 숨겼어요."
  end

  def unhide
    owned_student!(@forum_post.user)
    @forum_post.update!(hidden: false, hidden_by: nil)
    redirect_back fallback_location: teacher_dashboard_path, notice: "숨김을 해제했어요."
  end

  private

  def set_forum_post
    @forum_post = ForumPost.find(params[:id])
  end
end
