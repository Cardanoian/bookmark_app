# Shared reading-report domain constants (2022 개정 국어 5~6학년군).
#
# Kept as plain Ruby constants (not DB rows) per RAILS_PLAN §13. Referenced by
# the AI services, the RubricScorable concern, and the background jobs so the
# 5축 루브릭·성취기준·프롬프트가 한 곳에서 관리된다.
module ReadingDomain
  # 5축 루브릭 키 (순서 고정 — 방사형 차트·가중치 계산에 사용).
  RUBRIC_AXES = %i[content emotion life structure spelling].freeze

  # 축별 한국어 라벨.
  AXIS_LABELS = {
    content: "내용 이해",
    emotion: "감상 표현",
    life: "삶과 연결",
    structure: "구성·근거",
    spelling: "맞춤법"
  }.freeze

  # 축별 2022 개정 국어 성취기준 코드.
  ACHIEVEMENT_STANDARDS = {
    content: "[6국05-03]",
    emotion: "[6국03-03]",
    life: "[6국05-06]",
    structure: "[6국03-05]",
    spelling: "[6국04-06]"
  }.freeze

  # 등급별 지급 포인트.
  LEVEL_POINTS = { "A" => 30, "B" => 20, "C" => 10 }.freeze

  # 가중치 미설정 학급용 기본값(모든 축 동일).
  DEFAULT_RUBRIC_WEIGHTS = { content: 1, emotion: 1, life: 1, structure: 1, spelling: 1 }.freeze

  # 손글씨 전사 프롬프트 — JSON {text} 강제.
  OCR_PROMPT = <<~PROMPT.freeze
    당신은 초등학생이 손으로 쓴 독후감 사진을 정확히 전사하는 도우미입니다.
    이미지에 보이는 글자를 원문 그대로, 줄바꿈을 살려 한국어로 옮겨 적으세요.
    맞춤법이나 문장을 임의로 고치지 말고, 읽을 수 없는 글자는 물음표(?)로 표시하세요.
    반드시 아래 JSON 스키마만 반환하고 다른 설명은 붙이지 마세요.
    {"text": "전사한 본문 전체"}
  PROMPT

  # 5축 발전적 첨삭 프롬프트 — 엄격한 JSON 스키마 강제.
  RUBRIC_PROMPT = <<~PROMPT.freeze
    당신은 2022 개정 국어과 성취기준에 기반해 초등학생 독후감을 "발전적으로" 첨삭하는
    친절한 국어 선생님입니다. 맞춤법만 고치지 말고 내용·감상·삶과의 연결·구성·표기를 진단하세요.

    다음 5개 축을 각각 0~5의 정수로 채점하세요.
    - content(내용 이해, [6국05-03]): 인물·사건·배경 파악
    - emotion(감상 표현, [6국03-03]): 생각과 느낌의 구체성
    - life(삶과 연결, [6국05-06]): 자신의 삶·경험과의 연관과 성찰(A등급 유도)
    - structure(구성·근거, [6국03-05]): 문장 연결·구성·고쳐쓰기
    - spelling(맞춤법, [6국04-06]): 표기 정확성

    등급 규칙: 삶과 적극적으로 연결하고 성찰이 드러나면 A, 감상은 있으나 삶 연결이 약하면 B,
    줄거리 요약 위주면 C. 포인트는 A=30, B=20, C=10.

    반드시 아래 JSON 스키마만 반환하고 다른 텍스트는 붙이지 마세요.
    {
      "level": "A|B|C",
      "rubric": { "content": 0, "emotion": 0, "life": 0, "structure": 0, "spelling": 0 },
      "praise": ["잘한 점 문장"],
      "fix": ["보완하면 좋을 점 문장"],
      "grow": [ { "text": "성장 제안 문장", "standard_code": "[6국05-06]" } ],
      "pts": 0
    }
  PROMPT

  # 독서 퀴즈 초안 생성 프롬프트 — 교사 검수 전 초안(P5.6). JSON {questions:[...]} 강제.
  QUIZGEN_PROMPT = <<~PROMPT.freeze
    당신은 초등학교 5~6학년이 읽은 책으로 4지선다 독서 퀴즈를 만드는 국어 선생님입니다.
    책의 제목과 줄거리를 바탕으로, 내용 이해를 돕는 쉬운 퀴즈 문항을 만들어 주세요.
    각 문항은 보기(choices) 4개와 정답 보기 인덱스(answer_index, 0부터 시작)를 포함해야 합니다.
    보기는 서로 겹치지 않게, 정답은 하나만 되도록 구성하세요.

    반드시 아래 JSON 스키마만 반환하고 다른 설명은 붙이지 마세요.
    {
      "questions": [
        { "prompt": "문항 질문", "choices": ["보기1", "보기2", "보기3", "보기4"], "answer_index": 0 }
      ]
    }
  PROMPT

  # 진위·표절 의심 보조 프롬프트 — 교사 보조용, JSON {suspicion, reasons[]}.
  VERIFY_PROMPT = <<~PROMPT.freeze
    당신은 초등학생 독후감의 진위와 표절 가능성을 교사가 판단하도록 돕는 보조자입니다.
    최종 판정을 내리지 말고, 의심 정도와 근거만 제시하세요.
    suspicion 은 0.0(정상)~1.0(강한 의심) 사이의 실수로 표현하고,
    reasons 에는 그렇게 본 근거를 짧은 한국어 문장으로 담으세요.

    반드시 아래 JSON 스키마만 반환하고 다른 설명은 붙이지 마세요.
    {"suspicion": 0.0, "reasons": ["근거 문장"]}
  PROMPT
end
