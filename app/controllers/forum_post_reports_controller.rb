# 토론 글 신고(reading_discussion 아동 안전). 토픽 경계 안에서 볼 수 있는 남의 글만 신고 가능
# (ForumPostReportPolicy). 1인 1신고(unique) — 중복은 500 없이 조용히 접수 처리한다.
# **자동 숨김은 하지 않는다**(또래 저작물 집단신고 괴롭힘 방지). 접수는 저자 학급 담임 대시보드의
# 사후 검토 신호가 되고, 실제 숨김은 담임/총괄의 수동 판단으로만 이뤄진다.
class ForumPostReportsController < ApplicationController
  before_action :require_reading_discussion!
  before_action :set_forum_post

  def create
    @report = @forum_post.forum_post_reports.build(user: current_user, reason: report_params[:reason])
    authorize @report, policy_class: ForumPostReportPolicy

    begin
      @report.save
    rescue ActiveRecord::RecordNotUnique
      # 동시 더블클릭이 유니크 인덱스에 걸린 경우 — 이미 신고한 것으로 간주(counter 재증가 없음).
    end

    redirect_to @forum_post.topic, notice: "신고가 접수됐어요. 선생님이 확인할 거예요. 고마워요!"
  end

  private

  def set_forum_post
    @forum_post = ForumPost.find(params[:forum_post_id])
  end

  def report_params
    params.fetch(:forum_post_report, {}).permit(:reason)
  end
end
