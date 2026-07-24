# 교무관리자 도구 공통 베이스(P6.4). 교무관리자(또는 총괄)만 접근 가능하며,
# 모든 조회는 자기 학교로 스코프한다(경계). 타역할·타학교 → 403.
class SchoolAdmin::BaseController < ApplicationController
  before_action :require_school_admin!
  # SchoolAdmin::* 네임스페이스는 require_school_admin! 역할 게이트로 일괄 인가한다(per-action Pundit 아님).
  skip_after_action :verify_authorized

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

  # 리포트의 5축 평균(rubric 있는 것만 집계, 누락축 → 0). { axis => Float }.
  # Relation 이면 SQL 집계(본문 미적재, 전교 규모에도 상수 메모리·1쿼리, #3),
  # Array 면 기존 인메모리 집계(이미 로드된 슬라이스 재사용). 두 경로는 값이 동일하다(parity 테스트).
  def axis_averages(reports)
    reports.respond_to?(:where) ? axis_averages_sql(reports) : axis_averages_in_memory(reports)
  end

  # SQL 집계: SUM(COALESCE(json_extract(rubric,'$.axis'),0)) / (rubric 있는 행 수).
  # 인메모리와 동일 의미(누락축→0, rubric 없으면 제외). 행 인스턴스화 없이 1쿼리.
  def axis_averages_sql(reports)
    scored = reports.where.not(rubric: nil).where("rubric != '{}'")
    count = scored.count
    return ReadingDomain::RUBRIC_AXES.index_with { 0.0 } if count.zero?

    sums = scored.pick(*ReadingDomain::RUBRIC_AXES.map { |axis|
      Arel.sql("SUM(COALESCE(json_extract(rubric, '$.#{axis}'), 0))")
    })
    ReadingDomain::RUBRIC_AXES.each_with_index.to_h do |axis, i|
      [ axis, (Array(sums)[i].to_f / count).round(2) ]
    end
  end

  # 인메모리 집계(Array 경로). SQL 경로의 parity 기준.
  def axis_averages_in_memory(reports)
    scored = reports.select { |report| report.rubric.present? }
    ReadingDomain::RUBRIC_AXES.index_with do |axis|
      next 0.0 if scored.empty?

      (scored.sum { |report| report.rubric_scores[axis].to_i }.to_f / scored.size).round(2)
    end
  end
end
