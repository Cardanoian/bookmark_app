# 계정 연동(MERGE) 학생 셀프서브 정책(account_linking_seasons_plan §Phase 3). BookIntroPolicy 미러:
# 학급 소속 학생만 연동 폼·미리보기·확정을 할 수 있다(교사·비학급·비로그인 차단). 실제 병합 가드
# (작년 계정 소유증명·학년도 경계·정지)는 Accounts::MergeService 가 트랜잭션 안에서 강제한다.
class AccountLinkPolicy < ApplicationPolicy
  def new?
    linkable?
  end

  def preview?
    linkable?
  end

  def confirm?
    linkable?
  end

  private

  def linkable?
    user&.student? && user.classroom_id.present?
  end
end
