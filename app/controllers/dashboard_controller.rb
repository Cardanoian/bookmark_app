class DashboardController < ApplicationController
  # 역할별 홈 화면 라우팅(표현용) — 로그인만 요구하고 특정 리소스를 인가하지 않는다.
  skip_after_action :verify_authorized

  def show
    case Current.user.role.to_sym
    when :teacher
      render "dashboard/teacher"
    when :school_admin
      render "dashboard/school_admin"
    when :librarian
      render "dashboard/librarian"
    when :superadmin
      redirect_to admin_root_path
    else
      # 학생 홈(menu_refactor 심화 §2.D.3): 발견·진행 중 미션 요약. 전체 기록은 내 서재로 이동.
      @home = StudentHomeQuery.new(Current.user, discovery_cycle: params[:discovery], recommend_cycle: params[:recommend],
                                                popular_cycle: params[:popular])
      # 미션 홈 진입점(challenge-mission-detail). 챌린지 카드와 대칭으로 개수만 노출하고, 상세 내역은
      # missions#index 가 맡는다(홈이 모든 미션을 펼치지 않는다 — §2.D.3 "홈에 전체 기록을 복제하지 않는다").
      @active_mission_count = @home.active_mission_count
      # 챌린지 홈 진입점(ChallengePolicy::Scope 와 동일한 학생 경계 = 전국 + 우리 학교). 카드에 개수만 노출.
      @joinable_challenge_count = Challenge.where(scope: :global)
                                           .or(Challenge.where(scope: :school, school_id: Current.user.school_id)).count
      render "dashboard/student"
    end
  end
end
