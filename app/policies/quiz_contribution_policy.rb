# 학생 출제 기여 정책(게임 재구성 Phase 3 §4). 작성(출제)은 **학급 소속 학생 본인**만 가능하다.
# 서버가 작성자·학급을 확정하므로 위조가 불가하고, 승인 전까지는 아무에게도 노출되지 않는다.
# 교사 검토·수정·승인/반려 경계는 Teacher::QuizContributionsController 가 owned_student! 로 강제한다
# (담임이 자기 학급 학생 기여만 — 크로스-학급 403). BookIntroPolicy 미러.
class QuizContributionPolicy < ApplicationPolicy
  def new?
    create?
  end

  def create?
    user&.student? && user.classroom_id.present?
  end
end
