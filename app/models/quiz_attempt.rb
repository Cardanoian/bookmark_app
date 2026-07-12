# 퀴즈 플레이 1회 기록(P5.6). 게임 포인트가 이미 지급된 뒤 남는 집계 근거.
class QuizAttempt < ApplicationRecord
  belongs_to :quiz
  belongs_to :user

  # 이번 판에서 실제 지급된 포인트(멱등 델타). 영속 컬럼이 아니라 record! 가
  # 채워 주는 임시 속성으로, 컨트롤러가 정직한 안내 메시지를 만들 때 쓴다(§1.2).
  attr_accessor :awarded_delta

  # 이 attempt 에서 해당 문항의 서버 권위 힌트 공개수(hint_reveal 채점 차감의 단일 진실, C1).
  # 클라이언트 주장이 아니라 이 값(hint_reveals 컬럼, DB)으로만 차감한다 — 위조·stale-cookie
  # replay 로도 바뀌지 않는다(§3.2b, EXECUTOR-NOTE #1).
  def revealed_count(question)
    (hint_reveals || {})[question.id.to_s].to_i
  end
end
