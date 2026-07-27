# 미션 학생 열람 전용 목록·상세(challenge-mission-detail-pages). 관리 CRUD 는 Teacher::MissionsController
# 에 있고, 여기서는 학생이 홈 미션 카드에서 진입하는 목록(index)과 세부 페이지(show — 상단 상세 +
# 하단 지정 도서 목록)만 다룬다. 인가는 MissionPolicy#index?(학생 전용)·#show?(record 기반 학급 경계)로
# 강제한다 — 이 컨트롤러의 필수전제(임의 학생이 타 학급/타 학교 미션을 열람하지 못하게 한다).
class MissionsController < ApplicationController
  # 진행 중인 우리 반 미션 목록. 홈(dashboard/student)은 개수 카드만 두고 상세 내역은 이 화면이 맡는다
  # (챌린지 홈 카드 → challenges#index 관용구 미러). 미션은 join 없이 자동 배정이므로 목록의 경계는
  # 본인 participation 이고, 홈 카드 개수(StudentHomeQuery#active_mission_count)와 스코프를 공유해
  # "N개 있어요"와 실제 목록이 어긋나지 않는다.
  def index
    authorize :mission, :index?
    @missions = StudentHomeQuery.new(current_user).active_missions
  end

  def show
    @mission = Mission.includes(mission_goals: :books).find(params[:id])
    authorize @mission
    return unless current_user.student?

    @participation = @mission.mission_participations.find_by(user: current_user)
    @progress = Missions::ProgressCalculator.new(@mission, current_user, participation: @participation).call
  end
end
