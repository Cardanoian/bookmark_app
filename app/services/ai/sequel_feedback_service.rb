module Ai
  # 뒷이야기 이어쓰기 격려 코멘트(review_service 미러, 훨씬 가벼움). 키가 있으면 Claude 경로,
  # 없거나 실패하면 규칙기반 폴백으로 항상 유효한 코멘트 문자열을 반환한다(무중단).
  #
  # 정직한 AI 사용: 평가 대상은 "책"이 아니라 프롬프트에 든 "학생이 쓴 뒷이야기 글"이라 환각이 없다
  # (review_service 원리와 동일). 격려형 — 칭찬 1~2개 + 부드러운 제안 1개, 점수·등급 금지.
  # 단, 뒷이야기가 아닌 글(자모 나열·같은 말 반복·이야기와 무관한 글)은 칭찬하지 않고 1~2문장으로
  # 이야기를 이어 써 달라고만 부탁한다(베타 리뷰: '테스트테스트…'에 "마음이 잘 전해져요"라고 칭찬함).
  class SequelFeedbackService
    # LLM 응답이 스키마를 벗어났을 때 → 폴백 신호.
    class InvalidResponse < StandardError; end

    # 초등 전학년(1학년 포함) 격려형 프롬프트. 학년군 분기 없음(창작 격려는 눈높이 무관하게 따뜻하게).
    # 책 내용 단정 금지·학생에게 쓰는 말투(해요체·호칭 금지)는 첨삭 프롬프트와 같은 ReadingDomain 상수를 쓴다.
    # 예시 따옴표는 작은따옴표만 — 큰따옴표를 흉내 내면 {"comment": ...} JSON 이 깨져 폴백으로 떨어진다.
    SYSTEM_INSTRUCTION = <<~PROMPT.freeze
      너는 초등학생(1~6학년 모두 포함)이 "뒷이야기 이어쓰기"로 창작한 글을 읽고 따뜻하게 격려하는 책갈피 도우미야.
      아이가 상상해서 쓴 글을 읽고 다음 규칙을 반드시 지켜서 코멘트를 써 줘.

      [먼저 확인 — 이야기를 이어 쓴 글인가요?]
      - 자음·모음만 늘어놓은 글(예: 'ㄱㅀㅀ ㅀㅇㄹ'), 같은 글자나 낱말만 되풀이한 글(예: '테스트테스트테스트', 'ㅋㅋㅋㅋ'), 뜻 없이 아무 글자나 누른 글, 광고처럼 이야기와 분명히 관계없는 글은 뒷이야기가 아니다.
      - 뒷이야기가 아니면 칭찬하지 않는다. 글에 없는 마음이나 노력을 짐작해서 칭찬하지도 않는다. 대신 1~2문장으로, 이야기가 어떻게 이어질지 직접 써 달라고 다정하게 부탁한다(예: '주인공이 다음에 무엇을 할지 두세 문장으로 이어 써 줄래요?').
      - 짧거나 맞춤법이 틀려도 이야기를 이어 쓰려고 한 흔적이 있으면 뒷이야기로 보고 아래 규칙대로 격려한다.

      [뒷이야기일 때]
      - 글에서 실제로 보이는 좋은 점(상상력·표현·인물·장면 등)을 1~2가지 구체적으로 칭찬한다. 학생 글을 인용할 때는 작은따옴표(' ') 안에 한 글자도 바꾸지 말고 그대로 옮긴다.
      - 부드러운 제안을 딱 1가지만 질문이나 권유로 더한다(예: '이런 장면도 상상해 보면 어때요?').
      - 점수·등급·별점을 절대 매기지 않는다.
      - 맞춤법 지적이나 훈계 대신, 다음 글을 쓰고 싶어지도록 따뜻하고 다정하게 말한다.
      - 2~4문장.

      #{ReadingDomain::BOOK_FACT_RULES}
      #{ReadingDomain::CHILD_VOICE_RULES}
      반드시 JSON 으로만 답한다: {"comment": "<격려 코멘트>"}
    PROMPT

    def initialize(client: ClaudeClient.new, fallback: RuleBasedSequelFeedback.new)
      @client = client
      @fallback = fallback
    end

    # 반환: 격려형 코멘트 문자열(항상 유효). 무키/실패/스키마이탈 시 규칙기반 폴백.
    def call(sequel)
      return fallback_comment(sequel) unless Ai::ConsentGate.llm_allowed?(sequel.user, client: @client)

      response = @client.generate(
        contents: build_contents(sequel),
        system_instruction: SYSTEM_INSTRUCTION,
        response_json: true
      )
      normalize(response)
    rescue ClaudeClient::NotConfigured, ClaudeClient::ApiError, InvalidResponse
      fallback_comment(sequel)
    end

    private

    def fallback_comment(sequel)
      @fallback.call(body: sequel.body, book_title: book_title(sequel))
    end

    # 맥락(책 제목·지은이)을 얹되, 평가 대상은 학생 글 전문(body)이다.
    def build_contents(sequel)
      prompt = +"책 제목: #{book_title(sequel).presence || '(미상)'}\n"
      prompt << "지은이: #{sequel.book&.author.presence || '(미상)'}\n\n"
      prompt << "학생이 이어 쓴 뒷이야기:\n#{sequel.body}"
      [ { role: "user", parts: [ { text: prompt } ] } ]
    end

    def book_title(sequel)
      sequel.book&.title.to_s
    end

    def normalize(response)
      raise InvalidResponse, "response was not a Hash" unless response.is_a?(Hash)

      comment = response["comment"].to_s.strip
      raise InvalidResponse, "comment was blank" if comment.blank?

      comment
    end
  end
end
