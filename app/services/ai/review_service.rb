module Ai
  # 5축 발전적 첨삭. 키가 있으면 Claude(LLM) 경로, 없거나 실패하면 규칙기반
  # 폴백으로 항상 유효한 리뷰 해시를 반환한다(무중단).
  class ReviewService
    # LLM 응답이 스키마를 벗어났을 때 → 폴백 신호.
    class InvalidResponse < StandardError; end

    def initialize(client: ClaudeClient.new, fallback: RuleBasedReview.new)
      @client = client
      @fallback = fallback
    end

    # 반환: { level:, rubric:{5축}, praise:[], fix:[], grow:[{text,standard_code}], pts: }
    # 학생 학급 학년으로 학년군(band)을 판별해 눈높이별 프롬프트/폴백을 태운다.
    def call(report)
      band = report.grade_band_key
      return fallback_review(report, band) unless Ai::ConsentGate.llm_allowed?(report.user, client: @client)

      response = @client.generate(
        contents: build_contents(report),
        system_instruction: ReadingDomain.rubric_prompt(band),
        response_json: true
      )
      normalize(response, band)
    rescue ClaudeClient::NotConfigured, ClaudeClient::ApiError, InvalidResponse
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

    # fix·grow 는 학년군 상한(ReadingDomain.feedback_limits)까지만 남긴다. 프롬프트가 "중요한 것부터,
    # 최대 N개"를 지시하지만 모델이 넘길 수 있어, 한두 가지에 집중하게 하는 계약을 여기서 보장한다.
    def normalize(response, band)
      raise InvalidResponse, "response was not a Hash" unless response.is_a?(Hash)

      rubric = normalize_rubric(response["rubric"])
      level = response["level"].to_s.upcase
      raise InvalidResponse, "invalid level #{level.inspect}" unless ReadingDomain::LEVEL_POINTS.key?(level)

      limits = ReadingDomain.feedback_limits(band)
      {
        level: level,
        rubric: rubric,
        praise: Array(response["praise"]).map(&:to_s),
        fix: Array(response["fix"]).map(&:to_s).first(limits[:fix]),
        grow: normalize_grow(response["grow"], band).first(limits[:grow]),
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

    # grow[].standard_code 는 학생 학년군의 성취기준 목록(ReadingDomain.standard_codes)에 있는 코드만 저장한다.
    # 학년군 제한을 프롬프트 지시에만 맡기지 않는 서버 검증이다 — 목록 밖 코드(다른 학년군·지어낸 코드)는
    # 빈 문자열로 바꾸고 제안 문장(text)은 살린다(학생에게 줄 조언까지 버리지 않는다).
    # 표기 흔들림은 정규화한 뒤 대조한다: 공백과 대괄호를 걷어 "6국05-06"·"[ 6국05-06 ]"도 "[6국05-06]"로
    # 알아본다. 정규화는 표기만 맞출 뿐 대조 대상은 그대로 목록이라 목록 밖 코드가 들어올 길은 없고,
    # 저장은 목록 표기(대괄호 포함)로 통일해 학생 화면·교사 편집이 같은 모양을 본다.
    def normalize_grow(raw, band)
      allowed = ReadingDomain.standard_codes(band).index_by { |code| code.delete("[]") }
      Array(raw).filter_map do |entry|
        next unless entry.is_a?(Hash)

        hash = entry.symbolize_keys
        code = hash[:standard_code].to_s.gsub(/[\s\[\]]/, "")
        { text: hash[:text].to_s, standard_code: allowed.fetch(code, "") }
      end
    end
  end
end
