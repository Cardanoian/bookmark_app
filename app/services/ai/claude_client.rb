require "json"

module Ai
  # Thin Faraday wrapper around the Anthropic Messages API (Claude).
  #
  # Raising is the contract: callers rescue NotConfigured/ApiError to decide
  # whether to fall back (규칙기반 첨삭) or disable a feature (사진 OCR).
  #
  # **왜 공식 anthropic gem 이 아니라 Faraday 인가**: 이 리포는 외부 HTTP 를 전부 Faraday +
  # `connection:` 주입으로 통일하고(`app/services/CLAUDE.md`), 테스트는 webmock·mocha 없이
  # `Faraday::Adapter::Test` 스텁만으로 네트워크를 차단한다. SDK 를 끼우면 이 클라이언트 하나만
  # 테스트 전략이 갈라지고 webmock 이라는 새 개발 의존성이 필요해진다. Messages API 는 단일
  # POST 엔드포인트라 직접 호출 비용이 낮아 관례 유지 쪽이 이득이 크다.
  #
  # **왜 대상이 만 14세 미만인 이 앱에서 Claude 인가**: Gemini API 추가약관은 "18세 미만이
  # 접근할 가능성이 높은 서비스"에서의 사용을 금지한다(동의·PII 제거로 면제되지 않는다).
  # Anthropic 상용약관은 API 입출력을 모델 학습에 쓰지 않는 것이 기본값이라, 미성년 대상
  # 제품을 안전장치(연령 확인·콘텐츠 필터·신고 경로·AI 고지) 조건으로 허용한다.
  class ClaudeClient
    # 키가 비어 있을 때. 폴백 신호.
    class NotConfigured < StandardError; end
    # HTTP 실패·파싱 실패. 폴백 신호.
    class ApiError < StandardError; end

    BASE_URL = "https://api.anthropic.com".freeze
    ENDPOINT = "/v1/messages".freeze
    # Anthropic 은 요청마다 이 헤더를 요구한다(모델 버전이 아니라 API 스키마 버전이라 고정).
    API_VERSION = "2023-06-01".freeze
    MODEL = "claude-haiku-4-5".freeze
    # Anthropic 은 max_tokens 가 **필수**다(Gemini 는 선택이라 없었다). 5축 첨삭 JSON·퀴즈 세트·
    # 손글씨 OCR 본문을 모두 덮는 값. Haiku 4.5 의 출력 상한이 64K 라 여유가 크다.
    DEFAULT_MAX_TOKENS = 4096

    # 키 존재 여부만으로 사용 가능 판단(네트워크 호출 없음).
    def self.available?
      new.configured?
    end

    # connection: 테스트에서 스텁 Faraday 연결을 주입(네트워크 차단).
    # 키 소스: ENV 가 있으면 우선, 없으면 credentials 폴백(운영자 대안 경로, docs/API_KEYS.md §5·§6).
    def initialize(api_key: ENV["ANTHROPIC_API_KEY"].presence || Rails.application.credentials.dig(:anthropic, :api_key), connection: nil)
      @api_key = api_key.to_s
      @connection = connection
    end

    def configured?
      @api_key.present?
    end

    # contents: **제공자 중립 메시지 배열** [{ role:, parts: [{ text: } | { inlineData: { mimeType:, data: } }] }].
    #   Gemini 시절 형태를 그대로 유지한다 — 7개 호출 서비스를 건드리지 않고 변환을 이 안에만 가두려는
    #   의도적 선택이다(신규 코드도 이 형태로 넘기면 된다).
    # system_instruction: 시스템 프롬프트. 문자열 또는 { parts: [{ text: }] } 해시 모두 받는다.
    # response_json: 하위호환 인자. **응답 텍스트는 항상 JSON 으로 파싱해 돌려준다** — 옛 Gemini
    #   클라이언트도 responseMimeType 설정과 무관하게 늘 파싱했으므로 그 동작을 그대로 보존한다.
    # generation_config: max_tokens·temperature·model 등 생성 설정 병합용.
    # 반환: 모델이 반환한 JSON 텍스트를 파싱한 Hash(또는 Array).
    def generate(contents:, system_instruction: nil, response_json: true, generation_config: {})
      raise NotConfigured, "anthropic api_key is blank" unless configured?

      response = connection.post(ENDPOINT) do |req|
        req.headers["x-api-key"] = @api_key
        req.headers["anthropic-version"] = API_VERSION
        req.headers["Content-Type"] = "application/json"
        req.body = JSON.generate(request_body(contents, system_instruction, generation_config))
      end

      raise ApiError, "claude responded with status #{response.status}" unless response.success?

      parse_json(extract_text(response.body))
    rescue Faraday::Error => e
      raise ApiError, "claude request failed: #{e.message}"
    end

    private

    def request_body(contents, system_instruction, generation_config)
      config = generation_config.to_h.symbolize_keys
      body = {
        model: config.delete(:model).presence || MODEL,
        # maxOutputTokens 는 Gemini 표기 — 옛 호출부가 넘겨도 받아 준다.
        max_tokens: (config.delete(:max_tokens) || config.delete(:maxOutputTokens) || DEFAULT_MAX_TOKENS).to_i,
        messages: build_messages(contents)
      }
      body[:system] = system_instruction_text(system_instruction) if system_instruction.present?
      body.merge!(config) if config.any?
      body
    end

    # Gemini 는 systemInstruction 을 Content 객체로 요구했지만 Anthropic 의 system 은 문자열이다.
    # 옛 Content 해시가 들어와도 텍스트만 뽑아 통과시킨다.
    def system_instruction_text(instruction)
      return instruction.to_s unless instruction.is_a?(Hash)

      parts = instruction[:parts] || instruction["parts"]
      Array(parts).filter_map { |part| (part[:text] || part["text"]).presence }.join("\n")
    end

    def build_messages(contents)
      Array(contents).filter_map do |entry|
        entry = entry.to_h
        blocks = Array(entry[:parts] || entry["parts"]).filter_map { |part| content_block(part) }
        next if blocks.empty?

        # Gemini 의 "model" 이 Anthropic 에서는 "assistant" 다(현재 호출부는 user 만 쓴다).
        role = (entry[:role] || entry["role"]).to_s == "model" ? "assistant" : "user"
        { role: role, content: blocks }
      end
    end

    def content_block(part)
      part = part.to_h
      text = part[:text] || part["text"]
      return { type: "text", text: text.to_s } if text.present?

      inline = part[:inlineData] || part["inlineData"] || part[:inline_data] || part["inline_data"]
      return nil if inline.blank?

      inline = inline.to_h
      {
        type: "image",
        source: {
          type: "base64",
          media_type: (inline[:mimeType] || inline["mimeType"] || inline[:media_type] || inline["media_type"]).to_s,
          data: (inline[:data] || inline["data"]).to_s
        }
      }
    end

    # 응답은 content 블록 배열이다. 도구를 쓰지 않으므로 text 블록만 이어 붙이면 된다.
    def extract_text(raw_body)
      payload = raw_body.is_a?(String) ? JSON.parse(raw_body) : raw_body
      blocks = payload["content"] || payload[:content]
      text = Array(blocks).filter_map do |block|
        block = block.to_h
        (block["text"] || block[:text]) if (block["type"] || block[:type]).to_s == "text"
      end.join
      raise ApiError, "claude response had no text block" if text.blank?

      text
    rescue JSON::ParserError => e
      raise ApiError, "claude response was not valid JSON: #{e.message}"
    end

    # Anthropic 에는 Gemini 의 responseMimeType 같은 JSON 강제 스위치가 없다. 프롬프트가
    # "JSON 만 반환"을 요구해도 모델이 ```json 코드펜스나 앞뒤 한 줄을 덧붙일 수 있으므로,
    # 펜스를 벗겨 한 번, 그래도 실패하면 첫 여는 괄호~마지막 닫는 괄호를 잘라 한 번 더 시도한다.
    # 두 번 다 실패해야 ApiError(=각 서비스의 규칙기반/오프라인 폴백)로 넘긴다.
    def parse_json(text)
      JSON.parse(strip_code_fence(text))
    rescue JSON::ParserError
      salvaged = text.to_s[/[\{\[].*[\}\]]/m]
      raise ApiError, "claude response was not valid JSON" if salvaged.blank?

      begin
        JSON.parse(salvaged)
      rescue JSON::ParserError => e
        raise ApiError, "claude response was not valid JSON: #{e.message}"
      end
    end

    def strip_code_fence(text)
      text.to_s.strip.sub(/\A```(?:json)?\s*/i, "").sub(/```\s*\z/, "").strip
    end

    def connection
      @connection ||= Faraday.new(url: BASE_URL, request: { open_timeout: 3, timeout: 30 }) do |faraday|
        # 이 클라이언트는 백그라운드 잡(OcrJob/AiReviewJob)과 저빈도 교사 동기 경로(진위검증/퀴즈 초안
        # 생성) 양쪽에서 쓰인다. timeout 은 재시도(최대 2회)·간헐 지연까지 덮도록 30s 로 둔다.
        # 재시도 상태코드는 Anthropic 규약: 429(rate limit)·500(api_error)·529(overloaded).
        # POST 는 retry 미들웨어 기본값(멱등 메서드)에 없으므로 명시해야 실제로 재시도된다.
        faraday.request :retry, max: 2, interval: 0.3, backoff_factor: 2,
                                 methods: [ :post ],
                                 retry_statuses: [ 429, 500, 529 ],
                                 exceptions: [ Faraday::TimeoutError, Faraday::ConnectionFailed ]
        faraday.adapter Faraday.default_adapter
      end
    end
  end
end
