# 학급 미션 참여(P4.11). join → 세션 플래그로 다음 작성 독후감에 mission_id 연결.
class MissionsController < ApplicationController
  before_action :set_mission, only: [ :show, :join ]

  def index
    authorize :mission, :index?
    @missions = Mission.where(classroom_id: current_user.classroom_id).order(created_at: :desc)
  end

  def show
    authorize :mission, :show?
  end

  def join
    authorize :mission, :join?
    return head :forbidden unless @mission.classroom_id == current_user.classroom_id

    session[:active_mission_id] = @mission.id
    redirect_to new_report_path, notice: "‘#{@mission.title}’ 미션에 참여했어요. 독후감을 써 볼까요?"
  end

  private

  def set_mission
    @mission = Mission.find(params[:id])
  end
end
