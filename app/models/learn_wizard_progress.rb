# 단계 학습 위저드(LearnController)의 진행 — 학생마다 한 행(지금 단계 + 단계별 답).
# 예전에는 세션 쿠키에 쌓아, 답을 합쳐 한글 약 750자만 돼도 쿠키 한도(4KB)를 넘어 500 이 났다(2026-09-13).
# 다섯 단계를 마치면 LearnController 가 답을 모아 미제출 독후감 초안을 만들고 이 행을 지운다.
class LearnWizardProgress < ApplicationRecord
  belongs_to :user

  validates :user_id, uniqueness: true
end
