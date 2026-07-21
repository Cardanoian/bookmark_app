# 계정 연동(MERGE) 교사 보조(account_linking_seasons_plan §Phase 4). 담임이 자기 학급의 **현재
# 학년도 학생(NEW placeholder)** 을 그 학생의 **작년 계정(OLD)** 과 병합한다. 세션 스왑은 없다(교사
# 세션 유지). 경계는 `owned_student!`(NEW 가 자기 학급 소속) + 서버 검증(OLD 가 자기 학교 과거 학년도)
# 으로 강제하며, 실제 병합·되돌리기 무결성은 `Accounts::MergeService`·`AccountMerge#reverse!` 가 맡는다.
class Teacher::AccountLinksController < Teacher::BaseController
  # 교사 되돌리기 시간창(총괄은 무제한). 창 밖은 총괄에게 위임.
  REVERSE_WINDOW = 14.days

  def index
    @merges = AccountMerge.where(to_classroom_id: teacher_classrooms.select(:id))
                          .includes(:surviving_user).order(created_at: :desc).limit(100)
  end

  # NEW(현재 학급 학생) 선택 + 후보 작년 계정 이름검색(?old_name=).
  def new
    @students = current_classroom_students
    @candidates = candidate_old_accounts(params[:old_name])
  end

  def create
    new_account = owned_student!(User.find_by(id: params[:new_account_id]))
    old_account = User.find_by(id: params[:old_account_id])

    unless valid_old_candidate?(old_account)
      redirect_to new_teacher_account_link_path(old_name: params[:old_name]),
                  alert: "연동할 작년 계정을 다시 확인해 주세요."
      return
    end

    service = Accounts::MergeService.new(old_account: old_account, new_account: new_account, performed_by: Current.user)
    result = service.call
    if result.ok?
      # 세션 스왑 없음(교사 세션 유지) — 커밋 후 사이드이펙트만 호출자가 돌린다.
      service.run_post_commit_side_effects!(result.surviving_user)
      redirect_to teacher_account_links_path, notice: "#{old_account.name} 학생의 작년 계정을 연동했어요."
    else
      redirect_to new_teacher_account_link_path, alert: merge_error_message(result.error_code)
    end
  end

  # 되돌리기(14일 창 안, 자기 학급 병합만).
  def reverse
    merge = AccountMerge.find(params[:id])
    owned_merge!(merge)

    if merge.reversed_at.present?
      redirect_to teacher_account_links_path, alert: "이미 되돌린 연동이에요."
    elsif merge.created_at < REVERSE_WINDOW.ago
      redirect_to teacher_account_links_path, alert: "되돌리기 기간(14일)이 지났어요. 총괄관리자에게 문의해 주세요."
    else
      result = merge.reverse!(performed_by: Current.user)
      redirect_to teacher_account_links_path, notice: reverse_notice(result)
    end
  end

  private

  def current_classroom_students
    User.where(classroom_id: teacher_classrooms.select(:id), role: :student).order(:name)
  end

  # 후보 작년 계정: 담임 학교의 과거 학년도 학급 소속 학생 중 이름 일치(최근 학년도 우선).
  def candidate_old_accounts(name)
    return User.none if name.blank?

    User.student.where(school_id: Current.user.school_id, name: name.strip)
        .joins(:classroom).where(classrooms: { academic_year: ...Classroom.current_academic_year })
        .order("classrooms.academic_year DESC")
  end

  # OLD 가 담임 학교의 과거 학년도 학생인지 서버 검증(위조 id 방지 — 병합 가드 이전 1차 방어).
  def valid_old_candidate?(old_account)
    return false unless old_account&.student?
    return false unless old_account.school_id == Current.user.school_id

    year = old_account.classroom&.academic_year
    year.present? && year < Classroom.current_academic_year
  end

  # 이 병합의 to_classroom(=병합 후 학생 소속)이 담임 학급인지 — 크로스학급 되돌리기 403.
  def owned_merge!(merge)
    owned_classroom!(Classroom.find_by(id: merge.to_classroom_id))
    merge
  end

  def reverse_notice(result)
    notice = "연동을 되돌렸어요."
    notice += " 되돌린 계정은 새로 로그인해야 해요." if result[:requires_new_login]
    notice
  end

  def merge_error_message(code)
    case code
    when :invalid_source, :invalid_target, :same_account
      "연동 조건이 맞지 않아요(작년 계정·현재 학급을 확인해 주세요)."
    when :suspended
      "정지된 계정은 연동할 수 없어요."
    when :claim_conflict, :consumed_conflict
      "이미 처리 중이거나 처리된 연동이에요."
    else
      "연동을 처리하지 못했어요. 잠시 후 다시 시도해 주세요."
    end
  end
end
