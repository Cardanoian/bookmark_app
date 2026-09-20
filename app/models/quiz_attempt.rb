# 퀴즈 플레이 1회 기록(P5.6). 게임 포인트가 이미 지급된 뒤 남는 집계 근거.
class QuizAttempt < ApplicationRecord
  belongs_to :quiz
  belongs_to :user

  # 이번 판에서 실제 지급된 포인트(멱등 델타)는 영속 컬럼이 아니다 — Games::QuizPlay::Result 가 들고
  # 나오고, 컨트롤러가 그 값으로 정직한 안내 메시지를 만든다(§1.2). points_awarded 는 델타가 아니라
  # "이번 점수 기준 만점 적립액"이다(상한 maximum() 불변식).

  # 확정된(제출을 마친) 기록인가. whoami 는 게임을 시작할 때 미확정(played_at nil) 행을 먼저 만든다.
  # 확정된 기록은 답안·점수·힌트 공개수·완료 시각이 다시 바뀌지 않는다(BUG_FIX_PLAN F1).
  def finalized?
    played_at.present?
  end

  # 이 attempt 에서 해당 문항의 서버 권위 힌트 공개수(hint_reveal 채점 차감의 단일 진실, C1).
  # 클라이언트 주장이 아니라 이 값(hint_reveals 컬럼, DB)으로만 차감한다 — 위조·stale-cookie
  # replay 로도 바뀌지 않는다(§3.2b, EXECUTOR-NOTE #1).
  def revealed_count(question)
    (hint_reveals || {})[question.id.to_s].to_i
  end

  # 이 문항의 힌트를 하나 더 공개한다(서버 카운터 +1). 공개했으면 true, 아니면 false(이미 다 공개했거나
  # **확정된 기록**). 확정된 기록의 힌트 공개수는 그 판의 점수를 매긴 근거라 다시 바뀌면 안 된다(F1 §3.3).
  #
  # 읽기-올리기-쓰기를 잠금 안에서 한다. 제출(Games::QuizPlay)도 같은 DB 쓰기 잠금 안에서 힌트 공개수를
  # 다시 읽고 확정하므로, 둘이 겹쳐도 공개가 먼저면 제출이 그 힌트를 차감하고, 제출이 먼저면 여기서 완료를
  # 보고 올리지 않는다 — 확정 점수와 힌트 기록이 어긋나지 않는다. 제출과 같은 조건(played_at IS NULL)으로
  # 갱신해, 행 잠금 없이 도는 DB 에서도 확정된 행은 바뀌지 않는다.
  def reveal_hint!(question)
    with_lock do
      next false if finalized?

      revealed = revealed_count(question)
      next false unless revealed < question.hints_list.length

      reveals = (hint_reveals || {}).merge(question.id.to_s => revealed + 1)
      raised = self.class.where(id: id, played_at: nil).update_all(hint_reveals: reveals, updated_at: Time.current)
      reload
      raised == 1
    end
  end
end
