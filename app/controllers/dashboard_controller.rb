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
      # 학생 홈(menu_refactor 심화 §2.D.3): 발견·이어하기·진행 중 미션 요약. 전체 기록은 내 서재로 이동.
      @home = StudentHomeQuery.new(Current.user)
      render "dashboard/student"
    end
  end
end
