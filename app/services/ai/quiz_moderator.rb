module Ai
  # 게시 전(pre-publish) 안전 검증기(Phase 2b §2b.3, R4/시나리오2). 워밍 잡이 AI 생성 세트를
  # 학생에게 게시하기 **전에** 통과 여부를 판정한다. 통과분만 게시하고, 실패분은 게시하지 않아
  # 이미 서빙 중인 오프라인 세트가 그대로 유지된다(원문 미노출).
  #
  # ⚠️ 정직화(과대주장 금지) — 이 검증기가 **보장하는 것은 정확히** 다음뿐이다:
  #   ① 구조 유효성: content_axis별 문항 수(CONTENT_COUNTS) 일치, 타입별 정답 형태
  #      (mcq_single 정답 정확히 1개·범위 내 / matching 정답키 개수·범위 / hint_reveal 힌트+타깃),
  #      보기/우측 상호 배타(중복 없음), 인덱스 범위.
  #   ② 결정적 한국어 금칙어 denylist 차단.
  #   ③ (선택) LLM 자가검토 — API 키가 있을 때만. 키 없으면 완전히 생략(무키 무중단).
  #
  #   **보장하지 않는 것**: 미묘한 환각 정답·편향·맥락 부적절·사실 오류. 이는 강제 게이트가 아니라
  #   신고(reported) + content_version 재생성 + 학급/학교 스코프 kill switch + 지표 모니터링으로
  #   사후 회수·격리한다(ADR 잔여위험). 무게이트는 사용자의 의식적 수용.
  class QuizModerator
    # 결정적 금칙어(아동 부적절 최소 차단). 명백한 욕설/폭력 표현만 최소로 둔다 —
    # 일반 도서 내용에 오탐하지 않도록 보수적으로 유지한다(안전 "보장" 아님, 최소 방어선).
    # 단일 진실은 Moderation::TextDenylist::QUIZ(토론 글은 오탐 위험 낱말을 뺀 FORUM 리스트를 쓴다).
    DENYLIST = Moderation::TextDenylist::QUIZ

    # LLM 자가검토가 부적절로 판정하는 임계(0.0 정상 ~ 1.0 강한 부적절).
    LLM_REJECT_THRESHOLD = 0.5

    Result = Struct.new(:pass, :reasons, keyword_init: true) do
      def pass? = pass
      def fail? = !pass
    end

    def initialize(client: ClaudeClient.new)
      @client = client
    end

    # set: QuizDraftService#content_set/offline_set 형태의 문항 해시 배열(symbol 키).
    # content_axis: 기대 구조를 고르는 캐시축 심볼(:mcq/:matching/:hint_reveal).
    # 반환: Result(pass?/reasons). 실패 → 호출자는 게시하지 않고 오프라인 유지.
    def review(set, content_axis:)
      axis = content_axis.to_sym
      reasons = structure_errors(set, axis) + denylist_errors(set)
      # 구조·금칙어를 이미 통과했고 키가 있을 때만 (선택) LLM 자가검토를 얹는다.
      reasons += llm_errors(set) if reasons.empty? && @client.configured?
      Result.new(pass: reasons.empty?, reasons: reasons)
    end

    private

    # ── ① 구조 유효성 ────────────────────────────────────────────────
    # 주의: content_axis별 count 의미가 다르다. mcq/hint_reveal 은 "문항 수"이지만
    # matching 은 단일 문항 1개에 CONTENT_COUNTS[:matching]개의 **쌍**을 담는다(set.size=1).
    def structure_errors(set, axis)
      items = Array(set)
      return matching_set_errors(items) if axis == :matching

      errors = []
      expected = ReadingDomain::CONTENT_COUNTS[axis]
      errors << "문항 수 불일치(#{items.size}≠#{expected})" unless items.size == expected

      items.each_with_index do |item, index|
        errors.concat(item_errors(item, axis, index))
      end
      errors
    end

    # matching 은 문항 1개(안에 count개 쌍). 문항 수 1 검증 + 쌍 검증을 분리한다.
    def matching_set_errors(items)
      return [ "matching 문항 수 불일치(#{items.size}≠1)" ] unless items.size == 1

      item_errors(items.first, :matching, 0)
    end

    def item_errors(item, axis, index)
      return [ "문항#{index} 형식 오류(Hash 아님)" ] unless item.is_a?(Hash)

      case axis
      when :mcq          then mcq_errors(item, index)
      when :matching     then matching_errors(item, index)
      when :hint_reveal  then hint_reveal_errors(item, index)
      else [ "알 수 없는 content_axis: #{axis}" ]
      end
    end

    def mcq_errors(item, index)
      errors = []
      choices = Array(item[:choices]).map(&:to_s)
      errors << "문항#{index} 보기 4개 아님(#{choices.size})" unless choices.size == 4
      errors << "문항#{index} 보기 중복(상호 배타 위반)" unless choices.uniq.size == choices.size
      idx = item[:answer_index]
      errors << "문항#{index} 정답 인덱스 범위 밖" unless idx.is_a?(Integer) && idx.between?(0, choices.size - 1)
      errors
    end

    # 게임 재구성 Phase 1: matching(vocab) **생성** 경로는 제거됐고 `ReadingDomain::CONTENT_COUNTS`
    # 에도 :matching 키가 없다(nil). 이 채점기 자체는 과거 기록·재배열 방지차 휴면 보존되므로,
    # 상수에 기대는 "쌍 수 == 기대치" 비교 대신 **자체 정합성**(좌/우 비어있지 않음·개수 일치·
    # 우측 상호배타·정답키 범위)만으로 nil-안전하게 검증한다(휴면 경로가 호출돼도 크래시·오작동 없음).
    def matching_errors(item, index)
      errors = []
      content = symbolized(item[:content])
      lefts = Array(content[:lefts]).map(&:to_s)
      rights = Array(content[:rights]).map(&:to_s)
      answer = item[:answer]

      errors << "문항#{index} matching 좌/우 결손" if lefts.empty? || rights.empty?
      errors << "문항#{index} matching 좌/우 개수 불일치(#{lefts.size}≠#{rights.size})" unless lefts.size == rights.size
      errors << "문항#{index} matching 우측 중복(상호 배타 위반)" unless rights.uniq.size == rights.size

      unless answer.is_a?(Hash) && answer.size == lefts.size
        return errors << "문항#{index} matching 정답키 개수 불일치"
      end

      answer.each_value do |right_index|
        ri = right_index.to_i
        errors << "문항#{index} matching 정답 인덱스 범위 밖" unless ri.between?(0, rights.size - 1)
      end
      errors
    end

    def hint_reveal_errors(item, index)
      errors = []
      content = symbolized(item[:content])
      hints = Array(content[:hints]).reject { |hint| hint.to_s.blank? }
      errors << "문항#{index} hint_reveal 힌트 부족(<2)" if hints.size < 2
      errors << "문항#{index} hint_reveal 타깃 결손" if item[:answer].to_s.blank?
      errors
    end

    # ── ② 결정적 금칙어 denylist ─────────────────────────────────────
    def denylist_errors(set)
      haystack = Array(set).map { |item| item_text(item) }.join(" ")
      hits = Moderation::TextDenylist.hits(haystack, list: Moderation::TextDenylist::QUIZ)
      hits.empty? ? [] : [ "금칙어 포함: #{hits.join(', ')}" ]
    end

    # 문항의 학생 노출 텍스트를 모두 이어 붙인다(금칙어 스캔용).
    def item_text(item)
      return item.to_s unless item.is_a?(Hash)

      content = symbolized(item[:content])
      [
        item[:prompt], item[:explanation], item[:answer],
        Array(item[:choices]),
        Array(content[:hints]),
        Array(content[:lefts]), Array(content[:rights])
      ].flatten.compact.map(&:to_s).join(" ")
    end

    # ── ③ (선택) LLM 자가검토 — 키 있을 때만 ─────────────────────────
    def llm_errors(set)
      response = @client.generate(
        contents: [ { role: "user", parts: [ { text: moderation_prompt(set) } ] } ],
        system_instruction: MODERATION_SYSTEM_PROMPT,
        response_json: true
      )
      score = response.is_a?(Hash) ? response["suspicion"].to_f : 0.0
      score >= LLM_REJECT_THRESHOLD ? [ "LLM 자가검토 부적절(#{score})" ] : []
    rescue ClaudeClient::NotConfigured, ClaudeClient::ApiError
      # 자가검토 실패는 거부 사유로 삼지 않는다(구조·금칙어는 이미 통과) — 무키/실패 무중단.
      []
    end

    def moderation_prompt(set)
      "다음 독서 게임 문항이 초등학생에게 부적절한지 검토하세요.\n#{Array(set).map { |item| item_text(item) }.join("\n")}"
    end

    MODERATION_SYSTEM_PROMPT = <<~PROMPT.freeze
      당신은 초등학생 학습 콘텐츠의 안전성을 점검하는 보조자입니다.
      폭력·혐오·성적 표현·차별 등 부적절 요소가 있으면 suspicion 을 높게 주세요.
      반드시 아래 JSON 스키마만 반환하세요.
      {"suspicion": 0.0, "reasons": ["근거"]}
    PROMPT

    def symbolized(value)
      value.is_a?(Hash) ? value.symbolize_keys : {}
    end
  end
end
