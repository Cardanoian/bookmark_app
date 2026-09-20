class ReportPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    return false unless user

    case user.role.to_sym
    when :superadmin
      true
    when :teacher
      teacher_of_classroom?
    when :student
      record.user_id == user.id
    when :school_admin, :librarian
      same_school?
    else
      false
    end
  end

  def create?
    user&.student?
  end

  def new?
    create?
  end

  def update?
    return false unless user

    record.user_id == user.id || teacher_of_classroom? || user.superadmin?
  end

  def edit?
    update?
  end

  # 목록 정리는 작성 학생 본인만 할 수 있다. 교사·관리자는 교육 기록을 대신 삭제하지 않는다.
  def destroy?
    user&.student? && record.user_id == user.id
  end

  # 고쳐쓰기는 작성자 본인만.
  def revise?
    user.present? && record.user_id == user.id
  end

  # 우수작 공유는 작성자 본인 또는 담당 교사(총괄 포함) + **담임 승인(reviewed) 후에만**.
  # 게시판은 학급을 넘어 열람되는 지면이라, 검토를 거치지 않은 글이 올라가면 되돌릴 수 없다
  # (approve? 가 record.submitted? 를 보는 것과 같은 이유의 상태 게이트다).
  #
  # `|| record.shared?` 는 **취소 경로를 열어 두기 위한 fail-safe** 다. 공유 중인 글이 어떤
  # 경위로든 미검토 상태가 되면(레거시 행·수동 조작) 공유를 걷을 방법이 없어 게시판에 박제된다.
  # ReportsController#submit_for_review 가 재제출 시 공유를 자동 해제하므로 정상 흐름에서는
  # 이 분기에 도달하지 않는다 — 핵심 방어가 아니라 마지막 안전장치다.
  #
  # 새로 공유하려면 **지금 제출(현재 버전)에 대한 유효한 승인**이어야 한다(`feedback_visible?` =
  # reviewed? && review_ready?) — 승인 표시만 남고 그 승인이 확인한 첨삭이 현재 글의 것이 아니면 막는다.
  def share?
    return false unless user
    return false unless author? || teacher_of_classroom? || user.superadmin?

    record.feedback_visible? || record.shared?
  end

  # 검토·승인은 학급 담임(또는 superadmin)만.
  def review?
    return false unless user

    teacher_of_classroom? || user.superadmin?
  end

  # 승인은 **현재 버전의 첨삭이 완성된 제출 글**에만(`Report#review_ready?` — 제출됨 + done + 루브릭 +
  # 완료 버전 == 현재 버전). 목록(`Teacher::ReviewsController#classroom_scope`)이 이미 초안을 거르고 화면이
  # 준비 중인 글의 승인 버튼을 숨기지만, 승인은 되돌릴 수 없는 확정(포인트·뱃지·진화·미션 캐스케이드)이라
  # URL 직접 요청·batch_approve 의 id 배열 위조에 대해 정책에서도 fail-closed 로 막는다.
  # `submitted?` 만 보던 때는 AI 처리 중인 글이 승인됐고, 그 뒤 저장된 첨삭이 교사가 읽지 않은 채 학생에게
  # 공개됐다(BUG_FIX_PLAN F3). 교사가 **확인한 버전**과의 대조는 요청값이 필요해 Report#approve! 가 한다.
  # 호출부: 일괄 승인은 이 술어로 거른 뒤 approve! 를 부르고, 단건 승인은 `review?` 로 인가한 뒤 approve! 의
  # 결과(:not_ready/:stale)로 안내한다(같은 조건을 approve! 가 트랜잭션 안에서 다시 본다 — 어느 쪽도 우회 못 한다).
  def approve?
    review? && record.review_ready?
  end

  # 같은 버전으로 첨삭을 다시 요청(실패했거나 대기·처리 중에 멈춘 글의 복구, F2 §4.4). 글쓴이와 담임.
  def retry_review?
    return false unless user
    return false unless author? || teacher_of_classroom? || user.superadmin?

    record.review_retryable?
  end

  private

  def author?
    record.user_id == user.id
  end

  def teacher_of_classroom?
    user.teacher? && record.classroom&.teacher_id == user.id
  end

  def same_school?
    user.school_id.present? && record.classroom&.school_id == user.school_id
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless user

      case user.role.to_sym
      when :superadmin
        scope.all
      when :teacher
        scope.where(classroom_id: Classroom.where(teacher_id: user.id).select(:id))
      when :student
        scope.where(user_id: user.id)
      when :school_admin, :librarian
        scope.joins(:classroom).where(classrooms: { school_id: user.school_id })
      else
        scope.none
      end
    end
  end
end
