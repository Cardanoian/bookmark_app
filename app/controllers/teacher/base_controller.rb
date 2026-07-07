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

  # 리포트 배열의 5축 평균(rubric 있는 것만 집계, 누락축 → 0). { axis => Float }.
  def axis_averages(reports)
    scored = reports.select { |report| report.rubric.present? }
    ReadingDomain::RUBRIC_AXES.index_with do |axis|
      next 0.0 if scored.empty?

      (scored.sum { |report| report.rubric_scores[axis].to_i }.to_f / scored.size).round(2)
    end
  end
end
