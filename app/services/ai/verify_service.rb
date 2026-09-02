module Ai
  # 진위·표절 의심 보조(교사 보조용) + 학급 내 유사도 계산.
  class VerifyService
    NEUTRAL = { suspicion: nil, reasons: [] }.freeze

    def initialize(client: ClaudeClient.new)
      @client = client
    end

    # 반환: { suspicion:, reasons: [], ai_status: } — ai_status 는 AI 축이 왜 그 결과인지의 사유다.
    #
    # **`ConsentGate.llm_allowed?` 의 반환값으로는 사유를 알 수 없다.** 그것은
    # `client.configured? && user&.ai_consented?` 라 "키 없음"과 "동의 없음"을 하나의 boolean 으로
    # 뭉갠다. 무키 환경에서는 게이트에서 즉시 걸러져 `generate` 가 호출조차 되지 않으므로
    # `ClaudeClient::NotConfigured` 는 **영영 raise 되지 않는다** — rescue 로 구분하려 하면
    # 무키를 "동의 없음"으로 오표기해 교사에게 거짓 안내를 하게 된다.
    # 그래서 게이트는 그대로 두고(PII 감사 단일 지점 규약 — consent_gate.rb 주석 참조)
    # 여기서 두 술어를 각각 읽어 사유를 만든다.
    def call(report)
      return NEUTRAL.merge(ai_status: :not_configured) unless @client.configured?
      return NEUTRAL.merge(ai_status: :no_consent) unless report.user&.ai_consented?
      # 두 술어가 모두 참이면 게이트도 참이다. 게이트를 한 번 더 통과시켜 "학생 PII → 외부 AI"
      # 경로가 반드시 ConsentGate 를 지난다는 규약(grep 감사 가능성)을 유지한다.
      return NEUTRAL.merge(ai_status: :no_consent) unless Ai::ConsentGate.llm_allowed?(report.user, client: @client)

      response = @client.generate(
        contents: build_contents(report),
        system_instruction: ReadingDomain::VERIFY_PROMPT,
        response_json: true
      )
      suspicion = response["suspicion"]
      {
        suspicion: suspicion,
        reasons: Array(response["reasons"]).map(&:to_s),
        # 응답은 왔는데 suspicion 이 비어 있는 경우가 있다(모델이 판단을 유보). 성공과 구분해야
        # 화면이 "판단 보류"만 덩그러니 띄우지 않는다.
        ai_status: suspicion.nil? ? :unavailable : :ok
      }
    rescue ClaudeClient::NotConfigured, ClaudeClient::ApiError => e
      # report.body(개인정보 소지)는 로그에 남기지 않는다 — 예외 메시지는 상태코드/클래스 정보뿐이다.
      Rails.logger.warn("VerifyService API failure: #{e.class}: #{e.message}")
      NEUTRAL.merge(ai_status: :failed)
    end

    # suspicion(0.0~1.0 실수)을 교사가 읽을 수 있는 3단계로 접는다. 화면에 날것의 소수를
    # 찍으면("의심 정도: 0.35") 척도를 모르는 사람에게 아무 의미가 없다.
    SUSPICION_BANDS = [
      [ 0.34, "낮음", "badge-success" ],
      [ 0.67, "보통", "badge-yellow" ]
    ].freeze

    def self.suspicion_label(value)
      return nil if value.nil?

      score = value.to_f
      band = SUSPICION_BANDS.find { |threshold, _, _| score < threshold }
      band ? [ band[1], band[2] ] : [ "높음", "badge-danger" ]
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
