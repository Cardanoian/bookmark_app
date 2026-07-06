# 전역 뱃지 카탈로그 CRUD(P7.3).
class Admin::BadgesController < Admin::BaseController
  before_action :set_badge, only: [ :show, :edit, :update, :destroy ]

  def index
    @badges = Badge.order(:key)
  end

  def show
  end

  def new
    @badge = Badge.new
  end

  def create
    @badge = Badge.new(badge_params)

    if @badge.save
      redirect_to admin_badge_path(@badge), notice: "‘#{@badge.name}’ 뱃지를 등록했어요."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @badge.update(badge_params)
      redirect_to admin_badge_path(@badge), notice: "뱃지를 수정했어요."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @badge.destroy
    redirect_to admin_badges_path, notice: "뱃지를 삭제했어요."
  end

  private

  def set_badge
    @badge = Badge.find(params[:id])
  end

  def badge_params
    params.require(:badge).permit(:key, :name, :icon, :condition_desc)
  end
end
