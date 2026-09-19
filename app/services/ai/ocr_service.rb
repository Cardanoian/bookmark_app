require "base64"

module Ai
  # 손글씨 사진 → 텍스트(서버 Claude Vision). 키가 없으면 Unavailable 을 던져
  # 호출자가 사진(OCR) 입력 모드를 비활성화하도록 한다. Tesseract 폴백 없음.
  #
  # **모델은 OCR 만 `claude-sonnet-5` 다**(나머지 AI 는 `ClaudeClient::MODEL` = Haiku 4.5). Haiku 는
  # 손글씨 한글 인식이 무너져(한글 CER 51%) OCR 에 쓸 수 없고, Sonnet 5 는 현행이던 Gemini
  # 3.5-flash-lite 와 같거나 낫다(0.47% vs 0.84%) — 실측은 docs/AI_MODEL_SELECTION.md §9.
  # Gemini 는 약관이 18세 미만 대상 서비스를 금지해 걷어냈다.
  #
  # 비용을 좌우하는 것은 사진 크기가 아니라 **생각하는 양**이다. 기본 effort 에서 사진만 줄이면 흐린
  # 글자를 붙들고 생각이 길어져 출력 토큰(입력의 5배 단가)이 2.5~4배로 불고, 한 번은 38s 로 클라이언트
  # 타임아웃(30s)을 넘었다. 그래서 effort 를 low 로 묶어 출력을 전사 분량으로 고정한 뒤, 긴 변을
  # MAX_EDGE 로 줄여 입력을 덜어 낸다(원본 기본 대비 1,000장당 $18.3 → $13.3, 정확도 차이는 반복 편차 안).
  class OcrService
    # 키 미설정 → 사진 모드 비활성 신호.
    class Unavailable < StandardError; end

    MODEL = "claude-sonnet-5".freeze
    EFFORT = "low".freeze
    # 1024 까지는 정확도가 유지되고 768 부터 무너졌다(강아지똥 CER 5%, 512 는 57%). 멀리서 찍은 사진·
    # 작은 글씨에 여유를 두려고 1568 에서 멈춘다.
    MAX_EDGE = 1568
    # 전사문은 한 쪽에 700토큰 안팎이다. 빽빽한 쪽과 low effort 의 짧은 생각까지 덮되, 잘리면
    # JSON 이 깨져 ApiError(= 실패 안내)로 가므로 넉넉히 둔다.
    MAX_TOKENS = 8192
    # 실측 최대 15.5s(effort low). 기본 30s 로 두면 흐린 사진에서 끊긴 요청을 재시도가 되풀이해
    # 같은 과금이 겹칠 수 있어(기본 effort 에서 38s 를 본 적이 있다) 넉넉히 둔다.
    READ_TIMEOUT = 60

    def initialize(client: ClaudeClient.new(read_timeout: READ_TIMEOUT))
      @client = client
    end

    # image_blob: Active Storage blob/attachment (open·download·content_type 응답).
    # 반환: 인식된 본문 텍스트(String).
    def call(image_blob)
      raise Unavailable, "anthropic api_key is blank; disable photo mode" unless @client.configured?

      response = @client.generate(
        contents: build_contents(image_blob),
        generation_config: { model: MODEL, max_tokens: MAX_TOKENS, output_config: { effort: EFFORT } }
      )
      # generate 는 JSON.parse 결과를 그대로 돌려주므로 Hash 가 아닐 수도 있다(String/Array).
      text = response.is_a?(Hash) ? response["text"].to_s : response.to_s
      raise ClaudeClient::ApiError, "claude ocr response text was blank" if text.blank?

      text
    end

    private

    def build_contents(image_blob)
      media_type, bytes = image_payload(image_blob)
      [
        {
          role: "user",
          parts: [
            { text: ReadingDomain::OCR_PROMPT },
            { inlineData: { mimeType: media_type, data: Base64.strict_encode64(bytes) } }
          ]
        }
      ]
    end

    # 긴 변을 MAX_EDGE 로 줄인 JPEG. 메모리에서만 만들고 variant 로 저장하지 않는다 — 아이 손글씨
    # 사본을 스토리지에 하나 더 남길 이유가 없다. JPEG 로 다시 쓰는 김에 두 가지가 따라온다:
    # Claude 가 받지 않는 형식(HEIC 등)이 풀리고, 메타데이터(촬영 위치 등)가 빠진다(방향은 먼저 바로잡는다).
    #
    # 축소가 안 되면 원본을 그대로 보낸다. libvips 가 없는 호스트에서는 ruby-vips 로딩이 `LoadError`
    # (StandardError 가 아니다)를 던지므로 함께 잡는다(ReportPhotosController#send_variant 와 같은 이유).
    def image_payload(image_blob)
      [ "image/jpeg", image_blob.open { |file| resized_jpeg(file) } ]
    rescue StandardError, LoadError => e
      Rails.logger.warn("OCR image resize skipped, sending original: #{e.class}")
      [ image_blob.content_type, image_blob.download ]
    end

    def resized_jpeg(file)
      resized = ImageProcessing::Vips.source(file)
        .resize_to_limit(MAX_EDGE, MAX_EDGE)
        .convert("jpg")
        .saver(quality: 85, strip: true)
        .call
      File.binread(resized.path)
    ensure
      resized&.close!
    end
  end
end
