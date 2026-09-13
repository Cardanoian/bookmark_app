# 단계 학습 위저드 정책(P5.5). 독후감을 쓰는 학생만 쓴다 — 마치면 독후감 초안을 만들고(ReportPolicy#create? 도
# 학생만), 진행을 학생 행(LearnWizardProgress)에 남긴다. 예전에는 로그인만 보아, 진행이 DB 행이 된 뒤로는 담임이
# 몇 단계 답하다 마지막에 막히면 고아 진행 행이 남았다(2026-09-13). 앱 화면에 교직원 진입점은 없다.
class LearnPolicy < ApplicationPolicy
  def index?
    user&.student?
  end

  def advance?
    index?
  end
end
