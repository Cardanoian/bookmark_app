module Ai
  # 학생 PII 를 외부 AI(Claude·OCR 은 Gemini)로 보내는 모든 서비스의 단일 게이트(P1-1). 키가
  # 있고(configured?) 그 학생이 AI 활용에 동의(User#ai_consented? — §1 개인정보 + §2 AI 동의)했을
  # 때만 true 다. 미동의·무키는 각 서비스가 기존 규칙기반/중립값으로 우아하게 강등한다(무키와 동형).
  #
  # 게이트는 **제공자 중립**이다 — 호출자가 자기 경로의 클라이언트를 `client:` 로 넘기므로,
  # OcrJob 은 GeminiClient 를, 나머지는 ClaudeClient 를 넘겨 각자의 키로 판정된다.
  #
  # ⚠️ 신규 AI 서비스가 학생 원문을 외부 모델로 보낸다면(book 기반 무-PII 경로가 아니라면) 반드시 이
  # 게이트를 경유해야 한다 — `grep ConsentGate` 1회로 학생 PII → 외부 AI 전 경로를 감사할 수 있다.
  # 현재 경유 경로: ReviewService(첨삭)·SequelFeedbackService(뒷이야기)·OcrJob(손글씨).
  module ConsentGate
    def self.llm_allowed?(user, client:)
      client.configured? && user&.ai_consented?
    end
  end
end
