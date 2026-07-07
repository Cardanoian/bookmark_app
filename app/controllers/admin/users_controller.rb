# 사용자 관리(P7.2). 전 계정 검색·조회·수정 + 정지/해제·비밀번호 초기화·역할 부여
# + 교사 가입 승인/취소(0.1).
class Admin::UsersController < Admin::BaseController
  before_action :set_user, only: [ :show, :edit, :update, :suspend, :unsuspend, :reset_password, :role, :approve, :unapprove ]

  def index
    scope = User.includes(:school, :classroom).order(:role, :name)
    scope = scope.where("name LIKE ?", "%#{User.sanitize_sql_like(params[:q])}%") if params[:q].present?
    scope = scope.where(role: params[:role]) if params[:role].present? && User.roles.key?(params[:role])
    scope = scope.where(school_id: params[:school_id]) if params[:school_id].present?
    scope = scope.where(role: :teacher, approved: false) if params[:pending].present?
    @users = scope
    @schools = School.order(:name)
  end

  def show
  end

  def edit
  end

  def update
    if @user.update(user_params)
      redirect_to admin_user_path(@user), notice: "계정 정보를 수정했어요."
    else
      render :edit, status: :unprocessable_entity
    end
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

  # 역할(role)·정지(suspended)는 전용 액션(role/suspend/unsuspend)에서만 변경한다.
  # 일반 update 에서 대량 할당으로 권한이 상승하지 않도록 허용 목록에서 제외한다.
  def user_params
    params.require(:user).permit(:name, :school_id, :classroom_id, :points)
  end
end
