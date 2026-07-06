# 퀴즈 플레이 1회 기록(P5.6). 게임 포인트가 이미 지급된 뒤 남는 집계 근거.
class QuizAttempt < ApplicationRecord
  belongs_to :quiz
  belongs_to :user
end
