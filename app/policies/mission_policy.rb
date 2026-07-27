# 미션 정책(P4.11). 참여(join)는 학생, 열람(show)은 학급 경계로 격리한다.
# 학생용 미션 상세를 최상위(resources :missions)로 노출하므로, 임의 학생이 타 학급/타 학교 미션을
# 열람하지 못하게 show? 를 report_policy.rb 미러의 role-case 로 강화한다(라우트 신설의 필수전제).
class MissionPolicy < ApplicationPolicy
  # 학생 미션 목록(missions#index) 전용. 목록 자체가 본인 participation 기반이라 학생만 연다
  # (교직원 미션 화면은 관리 CRUD 인 Teacher::MissionsController 로 분리돼 있다).
  def index?
    user&.student?
  end

  def show?
    return false unless user

    case user.role.to_sym
    when :superadmin
      true
    when :teacher
      # 교사는 classroom_id 가 nil 이라 학생 규칙 재사용 불가 — 담임 관계로 경계를 판정한다.
      record.classroom&.teacher_id == user.id
    when :student
      record.classroom_id == user.classroom_id && record.published?
    when :school_admin, :librarian
      same_school?
    else
      false
    end
  end

  def join?
    user&.student?
  end

  private

  def same_school?
    user.school_id.present? && record.classroom&.school_id == user.school_id
  end
end
