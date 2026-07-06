module Ai
  # 진위·표절 의심 보조(교사 보조용) + 학급 내 유사도 계산.
  class VerifyService
    NEUTRAL = { suspicion: nil, reasons: [] }.freeze

    def initialize(client: GeminiClient.new)
      @client = client
    end

    # 반환: { suspicion:, reasons: [] }. 키 없음/실패 시 중립값.
    def call(report)
      return NEUTRAL.dup unless @client.configured?

      response = @client.generate(
        contents: build_contents(report),
        system_instruction: ReadingDomain::VERIFY_PROMPT,
        response_json: true
      )
      { suspicion: response["suspicion"], reasons: Array(response["reasons"]).map(&:to_s) }
    rescue GeminiClient::NotConfigured, GeminiClient::ApiError
      NEUTRAL.dup
    end

    # 같은 학급 다른 독후감들과의 최대 토큰 겹침(Jaccard). 0.0..1.0.
    # report.similarity 를 채우는 데 사용(순수 Ruby, 외부 호출 없음).
    def self.max_similarity(report)
      tokens = tokenize(report.body)
      return 0.0 if tokens.empty?

      others = report.classroom.reports.where.not(id: report.id)
      similarities = others.filter_map do |other|
        other_tokens = tokenize(other.body)
        jaccard(tokens, other_tokens) unless other_tokens.empty?
      end
      similarities.max || 0.0
    end

    def self.tokenize(text)
      text.to_s.downcase.scan(/\p{Word}+/).uniq
    end

    def self.jaccard(left, right)
      return 0.0 if left.empty? || right.empty?

      intersection = (left & right).size
      union = (left | right).size
      union.zero? ? 0.0 : (intersection.to_f / union).round(4)
    end

    private

    def build_contents(report)
      [ { role: "user", parts: [ { text: report.body.to_s } ] } ]
    end
  end
end
