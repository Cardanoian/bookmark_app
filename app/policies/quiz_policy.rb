# 퀴즈 정책(P5.6 → Phase 3 §3.3 경계 클램프). 게시된(published) 퀴즈는 로그인 학생/교사가
# 열람·플레이 가능하되, 학생의 **플레이·제출 시점**에 경계를 강제한다(N2/#2/#3):
#   · origin=system(온디맨드 캐시): band 서버계산 일치(`quiz.band == band_for(학급 학년)`) 아니면 403.
#   · origin=teacher: 학급-스코프 퀴즈는 소속 학급만(전역 퀴즈는 전체). raw quiz_id 경로에도
#     적용되어 **선존 크로스-학급 published 퀴즈 id 플레이 구멍**도 닫는다.
# 생성·수정은 교사/총괄만(manage?). 총괄·교사는 전권(경계 클램프 면제 — 미리보기/관리).
class QuizPolicy < ApplicationPolicy
  def show?
    return false unless user
    return true if manage?
    return false unless record.published?

    playable_for_student?
  end

  def create?
    manage?
  end

  def update?
    manage?
  end

  def new?
    create?
  end

  def edit?
    update?
  end

  private

  def manage?
    user&.teacher? || user&.superadmin?
  end

  # 학생 플레이 경계: system 은 band 서버계산 일치, teacher 는 학급 경계.
  def playable_for_student?
    if record.origin == "system"
      within_band?
    else
      within_classroom?
    end
  end

  # 온디맨드 system 퀴즈는 학생 학급 학년으로 서버계산한 band 와 일치해야 한다(사용자 입력 불신).
  # band 를 params 로 조작해도 리졸버가 서버계산하므로, 여기서 다른 band 행을 id 로 직접 치면 403.
  def within_band?
    record.band == ReadingDomain.band_for(user.classroom&.grade).to_s
  end

  # 교사 퀴즈: 전역(global)은 전체 공개, 학급-스코프(classroom)는 소속 학급 학생만.
  def within_classroom?
    return true if record.scope == "global"

    record.classroom_id.present? && record.classroom_id == user.classroom_id
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user
      return scope.all if user.teacher? || user.superadmin?

      scope.published
    end
  end
end
