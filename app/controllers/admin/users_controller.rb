# 사용자 관리(P7.2). 전 계정 검색·조회·수정 + 정지/해제·비밀번호 초기화·역할 부여
# + 교사 가입 승인/취소(0.1).
class Admin::UsersController < Admin::BaseController
  before_action :set_user, only: [ :show, :edit, :update, :suspend, :unsuspend, :reset_password, :role, :approve, :unapprove ]

  PER_PAGE = 50

  def index
    scope = User.includes(:school, :classroom).order(:role, :name)
    scope = scope.where("name LIKE ?", "%#{User.sanitize_sql_like(params[:q])}%") if params[:q].present?
    scope = scope.where(role: params[:role]) if params[:role].present? && User.roles.key?(params[:role])
    scope = scope.where(school_id: params[:school_id]) if params[:school_id].present?
    scope = scope.where(role: :teacher, approved: false) if params[:pending].present?
    @page, @has_next_page, @users = paginate(scope)
    @schools = School.order(:name)
  end

  def show
  end

  def edit
  end

  def update
    target = params.dig(:user, :points)

    # 포인트 목표값은 0 이상의 정수만 허용한다. 음수·비정수는 저장 없이 정확히 거부한다 —
    # 예전엔 음수 target 이면 spend_points! 가 조용히 실패(잔액 초과)하는데도 "수정했어요"라고
    # 거짓 안내했다(#9 후속: 보안 무해, UX 정합).
    if target.present? && !non_negative_integer?(target)
      @user.assign_attributes(user_params)
      # :base 로 담아 full_messages 가 속성명 접두사 없이 완결된 한국어 문장을 그대로 보이게 한다
      # (edit 뷰가 errors.full_messages 를 렌더 — :points 로 담으면 "Points ..." 처럼 어색해짐).
      @user.errors.add(:base, "포인트는 0 이상의 정수만 입력할 수 있어요.")
      return render :edit, status: :unprocessable_entity
    end

    return render :edit, status: :unprocessable_entity unless @user.update(user_params)

    notice =
      if target.present? && !adjust_points(@user, target)
        "계정 정보는 저장했지만, 포인트는 잔액을 초과해 조정하지 못했어요."
      else
        "계정 정보를 수정했어요."
      end
    redirect_to admin_user_path(@user), notice: notice
  end

  def suspend
    @user.update!(suspended: true)
    redirect_to admin_user_path(@user), notice: "‘#{@user.name}’ 계정을 정지했어요."
  end

  def unsuspend
    @user.update!(suspended: false)
    redirect_to admin_user_path(@user), notice: "‘#{@user.name}’ 계정 정지를 해제했어요."
  end

  def approve
    @user.update!(approved: true)
    redirect_to admin_user_path(@user), notice: "‘#{@user.name}’ 계정을 승인했어요."
  end

  def unapprove
    @user.update!(approved: false)
    redirect_to admin_user_path(@user), notice: "‘#{@user.name}’ 계정 승인을 취소했어요."
  end

  def reset_password
    temporary_password = User.generate_temporary_password
    @user.update!(password: temporary_password)
    redirect_to admin_user_path(@user), notice: "비밀번호를 임시 비밀번호 ‘#{temporary_password}’ 로 초기화했어요."
  end

  def role
    new_role = params[:role].to_s
    unless User.roles.key?(new_role)
      redirect_to admin_user_path(@user), alert: "허용되지 않은 역할입니다."
      return
    end

    @user.update!(role: new_role)
    redirect_to admin_user_path(@user), notice: "역할을 ‘#{new_role}’ (으)로 바꿨어요."
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  # 관리자 포인트 조정을 델타로 환산해 award_points 연쇄(뱃지·진화·랭킹)를 태운다(#9).
  # raw :points 대입은 게임 루프 후크를 우회하므로 금지 — 목표값과의 차액만 반영한다.
  # 진화는 단조라 음수 조정에서 check_evolution! 재평가는 불필요(ai_review_job 과 동일 정책).
  # 반환값: 조정이 실제 반영되면 true, 잔액을 초과해 차감이 거부되면 false(정직한 안내용).
  def adjust_points(user, target)
    delta = target.to_i - user.points.to_i
    return true if delta.zero?

    if delta.positive?
      user.award_points(delta, reason: "admin_adjustment")
      true
    else
      # 음수 조정은 도메인 원자 차감 프리미티브(spend_points!)로 처리한다(read-modify-write·raw SQL 회피).
      # target ≥ 0 을 이미 검증했으므로 정상 흐름에선 잔액 이내라 성공하지만, 동시 변경 등으로 잔액을
      # 초과하면 차감이 거부되고 false 를 돌려 호출자가 거짓 성공 대신 정직히 안내하게 한다.
      return false unless user.spend_points!(delta.abs)

      user.reload
      user.refresh_badges!
      user.broadcast_ranking_change
      true
    end
  end

  # 포인트 목표값 검증: 앞뒤 공백을 제외하고 0 이상의 정수 문자열만 참(음수·소수·문자 거부).
  def non_negative_integer?(value)
    value.to_s.strip.match?(/\A\d+\z/)
  end

  # 역할(role)·정지(suspended)는 전용 액션(role/suspend/unsuspend)에서만 변경한다.
  # 포인트(:points)는 대량 할당에서 제외하고 award_points 델타(adjust_points)로만 조정한다(#9).
  # 일반 update 에서 대량 할당으로 권한이 상승하지 않도록 허용 목록에서 제외한다.
  def user_params
    params.require(:user).permit(:name, :school_id, :classroom_id)
  end
end
