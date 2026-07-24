# 내 서재(menu_refactor 심화 §2.D.4). 현재 학생의 책별 활동 포트폴리오(읽기 전용).
# 표현·본인전용(StudentLibraryQuery 가 Current.user 로 스코프)이라 verify_authorized 를 스킵한다.
class LibrariesController < ApplicationController
  skip_after_action :verify_authorized
  before_action :require_student!

  # kind 필터: nil(전체) | reports(독후감 있음) | games(게임 기록 있음)
  def show
    @kind = params[:kind].presence
    query = StudentLibraryQuery.new(Current.user, kind: @kind)
    @entries = query.entries
    @legacy_groups = query.legacy_report_groups
  end

  private

  def require_student!
    redirect_to root_path unless Current.user&.student?
  end
end
