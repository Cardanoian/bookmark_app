# 미션 학생 열람 전용 상세(challenge-mission-detail-pages Step 3). 관리 CRUD 는 Teacher::MissionsController
# 에 있고, 여기서는 학생이 홈 미션 카드에서 진입하는 세부 페이지(상단 상세 + 하단 지정 도서 목록)만
# show 한다. 인가는 record 기반 MissionPolicy#show?(학급 경계)로 강제한다 — 이 컨트롤러 신설의 필수전제
# (임의 학생이 타 학급/타 학교 미션을 열람하지 못하게 한다). 진행상황은 학생 뷰어일 때만 계산한다.
class MissionsController < ApplicationController
  def show
    @mission = Mission.includes(mission_goals: :books).find(params[:id])
    authorize @mission
    return unless current_user.student?

    @participation = @mission.mission_participations.find_by(user: current_user)
    @progress = Missions::ProgressCalculator.new(@mission, current_user, participation: @participation).call
  end
end
