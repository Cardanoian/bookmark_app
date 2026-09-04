require "json"

module Ai
  # Thin Faraday wrapper around the Gemini generateContent endpoint.
  #
  # Raising is the contract: callers rescue NotConfigured/ApiError to decide
  # whether to fall back (규칙기반 첨삭) or disable a feature (사진 OCR).
  #
  # **용도는 손글씨 OCR 하나뿐이다.** 이 앱의 기본 AI 제공자는 Anthropic Claude(`Ai::ClaudeClient`)이고,
  # 5축 첨삭·뒷이야기·줄거리·퀴즈 초안·퀴즈 검수는 전부 거기로 간다. Gemini 는 Claude Haiku 의
  # 손글씨 인식 품질이 실사용에서 쓸 수 없는 수준이라 **OCR 경로만** 되돌린 것이다(`Ai::OcrService`).
  # 새 AI 기능을 붙일 때 기본 선택지는 `ClaudeClient` 이며, 이 클라이언트를 재사용하지 않는다.
  #
  # ⚠️ **약관 주의**: Gemini API 추가약관은 "18세 미만이 접근할 가능성이 높은 서비스"에서의 사용을
  # 금지하며, 이 금지는 보호자 동의를 받거나 PII 를 제거해도 면제되지 않는다(금지 대상이 데이터가
  # 아니라 서비스 자체다). 초등 전학년 대상인 이 앱에서 OCR 경로는 그 예외를 감수한 **의도적 결정**
  # 이므로, 나머지 경로까지 Gemini 로 넓히지 말 것. 배경은 커밋 b16facb 참고.
  class GeminiClient
    # 키가 비어 있을 때. 폴백 신호.
    class NotConfigured < StandardError; end
    # HTTP 실패·파싱 실패. 폴백 신호.
    class ApiError < StandardError; end

    BASE_URL = "https://generativelanguage.googleapis.com".freeze
    MODEL = "gemini-3.5-flash-lite".freeze
    ENDPOINT = "/v1beta/models/#{MODEL}:generateContent".freeze

    # 키 존재 여부만으로 사용 가능 판단(네트워크 호출 없음).
    def self.available?
      new.configured?
    end

    # connection: 테스트에서 스텁 Faraday 연결을 주입(네트워크 차단).
    # 키 소스: ENV 가 있으면 우선, 없으면 credentials 폴백(운영자 대안 경로, docs/API_KEYS.md §5·§6).
    def initialize(api_key: ENV["GEMINI_API_KEY"].presence || Rails.application.credentials.dig(:gemini, :api_key), connection: nil)
      @api_key = api_key.to_s
      @connection = connection
    end

    def configured?
      @api_key.present?
    end

    # contents: Gemini contents 배열. system_instruction: 선택.
    # response_json: true 면 responseMimeType 을 application/json 으로 강제.
    # generation_config: 지원되는 모델별 생성 설정 병합용.
    # 반환: 모델이 반환한 JSON 텍스트를 파싱한 Hash.
    def generate(contents:, system_instruction: nil, response_json: true, generation_config: {})
      raise NotConfigured, "gemini api_key is blank" unless configured?

      response = connection.post(ENDPOINT) do |req|
        req.params["key"] = @api_key
        req.headers["Content-Type"] = "application/json"
        req.body = JSON.generate(request_body(contents, system_instruction, response_json, generation_config))
      end

      raise ApiError, "gemini responded with status #{response.status}" unless response.success?

      parse_candidate(response.body)
    rescue Faraday::Error => e
      raise ApiError, "gemini request failed: #{e.message}"
    end

    private

    def request_body(contents, system_instruction, response_json, generation_config)
      body = { contents: contents }
      body[:systemInstruction] = system_instruction_content(system_instruction) if system_instruction.present?

      config = generation_config.to_h.dup
      config[:responseMimeType] = "application/json" if response_json
      body[:generationConfig] = config if config.any?
      body
    end

    # Gemini 는 systemInstruction 을 Content 객체({ parts: [{ text: }] })로 요구한다.
    # 문자열을 그대로 넣으면 HTTP 400(INVALID_ARGUMENT)이므로 감싸 준다.
    # 이미 구조화된 Hash(Content)면 그대로 통과시킨다.
    def system_instruction_content(instruction)
      return instruction if instruction.is_a?(Hash)

      { parts: [ { text: instruction.to_s } ] }
    end

    def parse_candidate(raw_body)
      payload = raw_body.is_a?(String) ? JSON.parse(raw_body) : raw_body
      text = payload.dig("candidates", 0, "content", "parts", 0, "text")
      raise ApiError, "gemini response had no text part" if text.blank?

      JSON.parse(text)
    rescue JSON::ParserError => e
      raise ApiError, "gemini response was not valid JSON: #{e.message}"
    end

    def connection
      @connection ||= Faraday.new(url: BASE_URL, request: { open_timeout: 3, timeout: 30 }) do |faraday|
        # 이 클라이언트는 백그라운드 잡(OcrJob) 한 곳에서만 쓰인다. 현재 모델(gemini-3.5-flash-lite)의
        # 손글씨 OCR 실측 지연은 2.5~4.4s(docs/AI_MODEL_SELECTION.md §4)지만, timeout 은 재시도(최대 2회)와
        # 긴 손글씨·간헐 지연까지 넉넉히 덮도록 30s 로 유지한다 — 과거 8s 는 (구 모델 gemini-2.5-flash 의
        # thinking 지연 시절) 매 시도를 타임아웃시켜 사진 모드를 사실상 무력화했다.
        # generateContent 호출은 POST 라서 methods 기본값(idempotent 메서드만)엔 없다 — 명시해야 실제로 재시도된다.
        faraday.request :retry, max: 2, interval: 0.3, backoff_factor: 2,
                                 methods: [ :post ],
                                 retry_statuses: [ 429, 503 ],
                                 exceptions: [ Faraday::TimeoutError, Faraday::ConnectionFailed ]
        faraday.adapter Faraday.default_adapter
      end
    end
  end
end
