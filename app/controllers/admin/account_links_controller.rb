# 계정 연동(MERGE) 총괄 보조(account_linking_seasons_plan §Phase 4). 총괄이 전 학교 병합을 감사·검색
# 하고 임의 병합·되돌리기(시간창 무제한)를 수행한다. **PII 경계**: 원장 `snapshot`(삭제 아동 계정의
# password_digest·name 등)은 뷰에 절대 덤프하지 않고, 요약(moved_counts·from/to·수행자·시각·reversed)만
# 렌더한다(AccountMerge 헤더 주석). 병합·되돌리기 무결성은 서비스·모델이 맡는다.
class Admin::AccountLinksController < Admin::BaseController
  PER_PAGE = 25

  def index
    scope = search(AccountMerge.includes(:surviving_user, :performed_by).order(created_at: :desc), params[:q])
    @page, @has_next, @merges = paginate(scope)
  end

  # 임의 병합(총괄 전권). id 로 old/new 를 직접 지정한다(서비스가 학년도·정지·학생 가드).
  def create
    old_account = User.find_by(id: params[:old_account_id])
    new_account = User.find_by(id: params[:new_account_id])
    service = Accounts::MergeService.new(old_account: old_account, new_account: new_account, performed_by: Current.user)
    result = service.call

    if result.ok?
      service.run_post_commit_side_effects!(result.surviving_user)
      redirect_to admin_account_links_path, notice: "계정을 연동했어요."
    else
      redirect_to admin_account_links_path, alert: "연동 실패: #{result.error_code}"
    end
  end

  # 되돌리기(총괄은 시간창 무제한).
  def reverse
    merge = AccountMerge.find(params[:id])

    if merge.reversed_at.present?
      redirect_to admin_account_links_path, alert: "이미 되돌린 연동이에요."
    else
      result = merge.reverse!(performed_by: Current.user)
      notice = "연동을 되돌렸어요."
      notice += " 되돌린 계정은 새로 로그인해야 해요." if result[:requires_new_login]
      redirect_to admin_account_links_path, notice: notice
    end
  end

  private

  # 생존자 이름으로 검색(현 신원 기준). snapshot 을 검색·노출하지 않는다.
  def search(scope, query)
    return scope if query.blank?

    survivor_ids = User.where("name LIKE ?", "%#{query.strip}%").select(:id)
    scope.where(surviving_user_id: survivor_ids)
  end
end
