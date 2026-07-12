# 담임교사 도구 공통 베이스(P6). 교사(또는 총괄)만 접근 가능하도록 인가하고,
# 담임 학급 스코프·소유 검증·5축 집계 같은 공통 로직을 제공한다. 비담임/타역할 → 403.
class Teacher::BaseController < ApplicationController
  before_action :require_teacher!
  # Teacher::* 네임스페이스는 require_teacher! 역할 게이트로 일괄 인가한다(per-action Pundit 아님).
  skip_after_action :verify_authorized

  private

  def require_teacher!
    raise Pundit::NotAuthorizedError unless Current.user&.teacher? || Current.user&.superadmin?
  end

  # 담임 학급들(총괄은 전체). 대시보드·문서출력의 기본 스코프.
  def teacher_classrooms
    if Current.user.superadmin?
      Classroom.all
    else
      Classroom.where(teacher_id: Current.user.id)
    end
  end

  # 특정 학급을 담임(또는 총괄)이 소유하는지 검증. 위반 시 403.
  def owned_classroom!(classroom)
    raise Pundit::NotAuthorizedError unless classroom &&
      (Current.user.superadmin? || classroom.teacher_id == Current.user.id)

    classroom
  end

  # 특정 학생이 담임 학급 소속인지 검증. 위반 시 403.
  def owned_student!(student)
    owned_classroom!(student&.classroom)
    student
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
