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

  # 본인이 낸 문제 모아보기(마이페이지 진입). 목록은 컨트롤러가 `current_user.quiz_contributions`
  # 로 이미 본인 것만 조회하므로 여기서는 역할만 판정한다. **create? 와 달리 학급 소속을 요구하지
  # 않는다** — 학급이 없어진(전학·학급 해체) 학생도 과거에 낸 문제는 되돌아볼 수 있어야 하고,
  # 목록은 새 기여를 만들지 않아 학급이 필요 없다.
  def index?
    user&.student?
  end
end
