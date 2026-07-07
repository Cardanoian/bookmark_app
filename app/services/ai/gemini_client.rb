require "json"

module Ai
  # Thin Faraday wrapper around the Gemini generateContent endpoint.
  #
  # Raising is the contract: callers rescue NotConfigured/ApiError to decide
  # whether to fall back (규칙기반 첨삭) or disable a feature (사진 OCR).
  class GeminiClient
    # 키가 비어 있을 때. 폴백 신호.
    class NotConfigured < StandardError; end
    # HTTP 실패·파싱 실패. 폴백 신호.
    class ApiError < StandardError; end

    BASE_URL = "https://generativelanguage.googleapis.com".freeze
    MODEL = "gemini-2.5-flash".freeze
    ENDPOINT = "/v1beta/models/#{MODEL}:generateContent".freeze

    # 키 존재 여부만으로 사용 가능 판단(네트워크 호출 없음).
    def self.available?
      new.configured?
    end

    # connection: 테스트에서 스텁 Faraday 연결을 주입(네트워크 차단).
    def initialize(api_key: Rails.application.credentials.dig(:gemini, :api_key), connection: nil)
      @api_key = api_key.to_s
      @connection = connection
    end

    def configured?
      @api_key.present?
    end

    # contents: Gemini contents 배열. system_instruction: 선택.
    # response_json: true 면 responseMimeType 을 application/json 으로 강제.
    # generation_config: temperature 등 추가 설정 병합용.
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
      body[:systemInstruction] = system_instruction if system_instruction.present?

      config = generation_config.to_h.dup
      config[:responseMimeType] = "application/json" if response_json
      body[:generationConfig] = config if config.any?
      body
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
      @connection ||= Faraday.new(url: BASE_URL, request: { open_timeout: 3, timeout: 8 }) do |faraday|
        # 이 클라이언트는 백그라운드 잡(OcrJob/AiReviewJob)과 저빈도 교사 동기 경로(진위검증/퀴즈 초안 생성)
        # 양쪽에서 쓰인다. max: 2 로 상한을 타이트하게 잡아 동기 경로 최악 대기시간을
        # timeout(8s) * (시도 1 + 재시도 2) = 24s 이내로 묶는다 — 저빈도 교사 액션이라 허용 가능.
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
