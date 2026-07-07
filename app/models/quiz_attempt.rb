# 퀴즈 플레이 1회 기록(P5.6). 게임 포인트가 이미 지급된 뒤 남는 집계 근거.
class QuizAttempt < ApplicationRecord
  belongs_to :quiz
  belongs_to :user

  # 이번 판에서 실제 지급된 포인트(멱등 델타). 영속 컬럼이 아니라 record! 가
  # 채워 주는 임시 속성으로, 컨트롤러가 정직한 안내 메시지를 만들 때 쓴다(§1.2).
  attr_accessor :awarded_delta
end
