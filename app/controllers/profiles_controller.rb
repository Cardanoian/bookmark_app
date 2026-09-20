class ProfilesController < ApplicationController
  def show
    authorize :profile, :show?

    @report_count = current_user.reports.count
    # '선생님 확인' 편수 = `reviewed` 플래그(목록의 `reports?reviewed=true` 필터와 같은 기준).
    # 첨삭을 보여 줘도 되는 글의 경계(`Report.approved`)와는 다르다 — BUG_FIX_PLAN §10.4.
    @reviewed_report_count = current_user.reports.where(reviewed: true).count
    @badge_count = current_user.badges.count
    @game_count = current_user.quiz_attempts.count
    @account_link_available = account_link_available?
  end

  private

  # 계정 연동(account_linking_seasons_plan §Phase 3) 진입점 노출 여부. 플래그 on + 학급 학생 +
  # 아직 이 계정이 연동 생존자가 아닐 때만(이미 연동했으면 숨김). AccountLinkPolicy 와 같은 조건 + 플래그.
  def account_link_available?
    return false unless current_user.student? && current_user.classroom_id.present?
    return false unless AppSetting.feature_enabled?("account_linking", scope: current_user.classroom, default: true)

    !AccountMerge.active.exists?(surviving_user_id: current_user.id)
  end
end
