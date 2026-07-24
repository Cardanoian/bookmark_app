module Ai
  # Gemini 줄거리 생성(게임 재구성 Phase 4, §1·§3.1). review_service·sequel_feedback_service 미러.
  # 키가 있으면 Gemini 에게 "이 책을 아는가? 알면 초등 눈높이 줄거리를 써라"를 물어, **확신 있는
  # 경우에만** 줄거리 문자열을 반환한다. 무키/실패/저확신/모름/스키마이탈은 nil 로 폴백(크래시 0).
  #
  # 정직화(§3.1 잔여위험 완화):
  #   - **기존 summary 는 프롬프트에 넣지 않는다** — 자기참조를 최소화한 독립 인식 테스트라야
  #     Gemini 가 진짜 아는 책인지 판별되고 자기 작화를 되먹이지 않는다(계획서 §3.1·P2-6).
  #   - 확신도(confidence) ≥ CONFIDENCE_THRESHOLD 이고 known=true 일 때만 저장 대상으로 반환한다.
  #   - "다른 책과 혼동/작화하지 마라"를 프롬프트로 명시해 confabulation 을 억제한다.
  class BookSummaryService
    # LLM 응답이 스키마를 벗어났을 때 → 폴백 신호.
    class InvalidResponse < StandardError; end

    # 이 값 미만의 확신도는 저장하지 않는다(무명 책 환각 방지). 운영 튜닝 여지 있음.
    CONFIDENCE_THRESHOLD = 0.7

    SYSTEM_INSTRUCTION = <<~PROMPT.freeze
      너는 초등학생 독서 교육을 돕는 책갈피 도우미야. 아래에 주어지는 책의 제목·지은이 등 서지 정보만 보고,
      네가 그 책을 실제로 확실히 아는지 판단해서 다음 규칙을 반드시 지켜 JSON 으로만 답해.
      - 그 책을 확실히 안다면 known 을 true 로 하고, 초등학생 눈높이에 맞는 쉬운 말로 줄거리를 4~6문장으로 써.
      - 확신 정도(confidence)를 0.0(전혀 모름)~1.0(매우 확신) 사이의 실수로 매겨.
      - 조금이라도 모르거나 헷갈리면 known 을 false 로 하고 summary 는 빈 문자열로 둬(모르면 모른다고 해).
      - 이 책을 다른 책과 절대 혼동하거나 지어내지 마. 확실하지 않으면 지어내느니 모른다고 답해.
      반드시 아래 JSON 스키마만 반환하고 다른 설명은 붙이지 마.
      {"known": true, "confidence": 0.0, "summary": "<줄거리 4~6문장 또는 빈 문자열>"}
    PROMPT

    def initialize(client: GeminiClient.new)
      @client = client
    end

    # 반환: 확신 있는 줄거리 문자열, 아니면 nil(무키·실패·저확신·모름·스키마이탈 모두 nil).
    def call(book)
      return nil unless @client.configured?

      response = @client.generate(
        contents: build_contents(book),
        system_instruction: SYSTEM_INSTRUCTION,
        response_json: true
      )
      confident_summary(response)
    rescue GeminiClient::NotConfigured, GeminiClient::ApiError, InvalidResponse
      nil
    end

    private

    # 서지 정보만 넣는다(기존 summary 는 넣지 않음 — 독립 인식 테스트, §3.1·P2-6).
    def build_contents(book)
      prompt = +"책 제목: #{book.title}\n"
      prompt << "지은이: #{book.author}\n" if book.author.present?
      prompt << "출판사: #{book.publisher}\n" if book.publisher.present?
      prompt << "ISBN: #{book.isbn}\n" if book.isbn.present?
      prompt << "\n이 책을 아는지 판단하고 규칙에 맞춰 JSON 으로 답해 주세요."
      [ { role: "user", parts: [ { text: prompt } ] } ]
    end

    # known=true AND confidence ≥ 임계 AND summary 비어있지 않음 일 때만 줄거리를 채택. 아니면 nil.
    def confident_summary(response)
      raise InvalidResponse, "response was not a Hash" unless response.is_a?(Hash)

      return nil unless response["known"] == true
      return nil unless response["confidence"].to_f >= CONFIDENCE_THRESHOLD

      summary = response["summary"].to_s.strip
      summary.presence
    end
  end
end
