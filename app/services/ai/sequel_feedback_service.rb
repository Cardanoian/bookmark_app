module Ai
  # 뒷이야기 이어쓰기 격려 코멘트(review_service 미러, 훨씬 가벼움). 키가 있으면 Gemini 경로,
  # 없거나 실패하면 규칙기반 폴백으로 항상 유효한 코멘트 문자열을 반환한다(무중단).
  #
  # 정직한 AI 사용: 평가 대상은 "책"이 아니라 프롬프트에 든 "학생이 쓴 뒷이야기 글"이라 환각이 없다
  # (review_service 원리와 동일). 격려형 — 칭찬 1~2개 + 부드러운 제안 1개, 점수·등급 금지.
  class SequelFeedbackService
    # LLM 응답이 스키마를 벗어났을 때 → 폴백 신호.
    class InvalidResponse < StandardError; end

    # 초등 전학년(1학년 포함) 격려형 프롬프트. 학년군 분기 없음(창작 격려는 눈높이 무관하게 따뜻하게).
    SYSTEM_INSTRUCTION = <<~PROMPT.freeze
      너는 초등학생(1~6학년 모두 포함)이 "뒷이야기 이어쓰기"로 창작한 글을 읽고 따뜻하게 격려하는 책갈피 도우미야.
      아이가 상상해서 쓴 글을 읽고 다음 규칙을 반드시 지켜서 코멘트를 써 줘.
      - 글에서 실제로 보이는 좋은 점(상상력·표현·인물·장면 등)을 1~2가지 구체적으로 칭찬한다.
      - 부드러운 제안을 딱 1가지만 권유형으로 더한다(예: "이런 장면도 상상해 보면 어때요?").
      - 점수·등급·별점을 절대 매기지 않는다.
      - 맞춤법 지적이나 훈계 대신, 다음 글을 쓰고 싶어지도록 따뜻하고 다정하게 말한다.
      - 2~4문장, 존댓말.
      반드시 JSON 으로만 답한다: {"comment": "<격려 코멘트>"}
    PROMPT

    def initialize(client: GeminiClient.new, fallback: RuleBasedSequelFeedback.new)
      @client = client
      @fallback = fallback
    end

    # 반환: 격려형 코멘트 문자열(항상 유효). 무키/실패/스키마이탈 시 규칙기반 폴백.
    def call(sequel)
      return fallback_comment(sequel) unless Ai::ConsentGate.gemini_allowed?(sequel.user, client: @client)

      response = @client.generate(
        contents: build_contents(sequel),
        system_instruction: SYSTEM_INSTRUCTION,
        response_json: true
      )
      normalize(response)
    rescue GeminiClient::NotConfigured, GeminiClient::ApiError, InvalidResponse
      fallback_comment(sequel)
    end

    private

    def fallback_comment(sequel)
      @fallback.call(body: sequel.body, book_title: book_title(sequel))
    end

    # 맥락(책 제목·지은이)을 얹되, 평가 대상은 학생 글 전문(body)이다.
    def build_contents(sequel)
      prompt = +"책 제목: #{book_title(sequel).presence || '(미상)'}\n"
      prompt << "지은이: #{sequel.book&.author.presence || '(미상)'}\n\n"
      prompt << "학생이 이어 쓴 뒷이야기:\n#{sequel.body}"
      [ { role: "user", parts: [ { text: prompt } ] } ]
    end

    def book_title(sequel)
      sequel.book&.title.to_s
    end

    def normalize(response)
      raise InvalidResponse, "response was not a Hash" unless response.is_a?(Hash)

      comment = response["comment"].to_s.strip
      raise InvalidResponse, "comment was blank" if comment.blank?

      comment
    end
  end
end
