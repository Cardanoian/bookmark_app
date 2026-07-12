# 퀴즈 플레이 기록 정책(P5.6 → Phase 3 §3.3). 플레이(생성)·힌트 공개(update)는 **대상 퀴즈를
# 플레이할 수 있는** 학생만 — 경계 클램프를 QuizPolicy#show? 에 위임해 한 곳에서 강제한다
# (band/학급/선존 크로스-학급 구멍 차단). 열람은 본인 기록만.
class QuizAttemptPolicy < ApplicationPolicy
  def create?
    playable?
  end

  # whoami 힌트 공개(reveal_hint): 본인 attempt 이면서 그 퀴즈를 플레이할 수 있어야 한다.
  def update?
    owner? && playable?
  end

  def show?
    owner?
  end

  private

  def owner?
    user.present? && record.user_id == user.id
  end

  # 대상 퀴즈의 플레이 경계(band/학급)를 QuizPolicy 로 위임한다.
  def playable?
    return false unless user

    QuizPolicy.new(user, record.quiz).show?
  end
end
