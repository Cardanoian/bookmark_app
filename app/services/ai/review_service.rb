module Ai
  # 5축 발전적 첨삭. 키가 있으면 Gemini(LLM) 경로, 없거나 실패하면 규칙기반
  # 폴백으로 항상 유효한 리뷰 해시를 반환한다(무중단).
  class ReviewService
    # LLM 응답이 스키마를 벗어났을 때 → 폴백 신호.
    class InvalidResponse < StandardError; end

    def initialize(client: GeminiClient.new, fallback: RuleBasedReview.new)
      @client = client
      @fallback = fallback
    end

    # 반환: { level:, rubric:{5축}, praise:[], fix:[], grow:[{text,standard_code}], pts: }
    # 학생 학급 학년으로 학년군(band)을 판별해 눈높이별 프롬프트/폴백을 태운다.
    def call(report)
      band = report.grade_band_key
      return fallback_review(report, band) unless @client.configured?

      response = @client.generate(
        contents: build_contents(report),
        system_instruction: ReadingDomain.rubric_prompt(band),
        response_json: true
      )
      normalize(response)
    rescue GeminiClient::NotConfigured, GeminiClient::ApiError, InvalidResponse
      fallback_review(report, band)
    end

    private

    def fallback_review(report, band)
      @fallback.call(body: report.body, book_title: report_book_title(report), band: band)
    end

    def build_contents(report)
      prompt = +"책 제목: #{report_book_title(report).presence || '(미상)'}\n\n"
      prompt << "독후감 본문:\n#{report.body}"
      [ { role: "user", parts: [ { text: prompt } ] } ]
    end

    def report_book_title(report)
      report.book&.title || report.book_title
    end

    def normalize(response)
      raise InvalidResponse, "response was not a Hash" unless response.is_a?(Hash)

      rubric = normalize_rubric(response["rubric"])
      level = response["level"].to_s.upcase
      raise InvalidResponse, "invalid level #{level.inspect}" unless ReadingDomain::LEVEL_POINTS.key?(level)

      {
        level: level,
        rubric: rubric,
        praise: Array(response["praise"]).map(&:to_s),
        fix: Array(response["fix"]).map(&:to_s),
        grow: normalize_grow(response["grow"]),
        pts: ReadingDomain::LEVEL_POINTS.fetch(level)
      }
    end

    def normalize_rubric(raw)
      raise InvalidResponse, "rubric was not a Hash" unless raw.is_a?(Hash)

      scores = raw.symbolize_keys
      ReadingDomain::RUBRIC_AXES.index_with do |axis|
        value = scores[axis]
        raise InvalidResponse, "missing axis #{axis}" if value.nil?

        score = value.to_i
        raise InvalidResponse, "axis #{axis} out of range" unless score.between?(0, 5)

        score
      end
    end

    def normalize_grow(raw)
      Array(raw).filter_map do |entry|
        next unless entry.is_a?(Hash)

        hash = entry.symbolize_keys
        { text: hash[:text].to_s, standard_code: hash[:standard_code].to_s }
      end
    end
  end
end
