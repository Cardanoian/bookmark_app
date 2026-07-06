# 교무관리자 도구 공통 베이스(P6.4). 교무관리자(또는 총괄)만 접근 가능하며,
# 모든 조회는 자기 학교로 스코프한다(경계). 타역할·타학교 → 403.
class SchoolAdmin::BaseController < ApplicationController
  before_action :require_school_admin!

  private

  def require_school_admin!
    raise Pundit::NotAuthorizedError unless Current.user&.school_admin? || Current.user&.superadmin?
  end

  # 교무관리자의 소속 학교(경계 스코프). 총괄은 school_id 파라미터로 학교를 선택할 수 있다.
  def current_school
    @current_school ||=
      if Current.user.superadmin?
        School.find_by(id: params[:school_id]) || Current.user.school
      else
        Current.user.school
      end
  end

  # 리포트 배열의 5축 평균(rubric 있는 것만 집계, 누락축 → 0). { axis => Float }.
  def axis_averages(reports)
    scored = reports.select { |report| report.rubric.present? }
    ReadingDomain::RUBRIC_AXES.index_with do |axis|
      next 0.0 if scored.empty?

      (scored.sum { |report| report.rubric_scores[axis].to_i }.to_f / scored.size).round(2)
    end
  end
end
