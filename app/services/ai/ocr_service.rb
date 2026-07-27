require "base64"

module Ai
  # 손글씨 사진 → 텍스트(서버 Gemini Vision). 키가 없으면 Unavailable 을 던져
  # 호출자가 사진(OCR) 입력 모드를 비활성화하도록 한다. Tesseract 폴백 없음.
  class OcrService
    # 키 미설정 → 사진 모드 비활성 신호.
    class Unavailable < StandardError; end

    def initialize(client: GeminiClient.new)
      @client = client
    end

    # image_blob: Active Storage blob/attachment (download·content_type 응답).
    # 반환: 인식된 본문 텍스트(String).
    def call(image_blob)
      raise Unavailable, "gemini api_key is blank; disable photo mode" unless @client.configured?

      response = @client.generate(
        contents: build_contents(image_blob),
        response_json: true
      )
      # generate 는 JSON.parse 결과를 그대로 돌려주므로 Hash 가 아닐 수도 있다(String/Array).
      text = response.is_a?(Hash) ? response["text"].to_s : response.to_s
      raise GeminiClient::ApiError, "gemini ocr response text was blank" if text.blank?

      text
    end

    private

    def build_contents(image_blob)
      encoded = Base64.strict_encode64(image_blob.download)
      [
        {
          role: "user",
          parts: [
            { text: ReadingDomain::OCR_PROMPT },
            { inlineData: { mimeType: image_blob.content_type, data: encoded } }
          ]
        }
      ]
    end
  end
end
