# Shared reading-report domain constants (2022 개정 국어과 교육과정, 교육부 고시 제2022-33호 [별책 5]).
#
# Kept as plain Ruby constants (not DB rows) per RAILS_PLAN §13. Referenced by
# the AI services, the RubricScorable concern, and the background jobs so the
# 5축 루브릭·성취기준·프롬프트가 한 곳에서 관리된다.
#
# 학년군(band) 분기: 대상이 초등 전학년이므로 5축 성취기준·프롬프트·추천활동을
# 1~2/3~4/5~6학년군으로 나눈다. 학생의 학급 학년(`classroom.grade`)으로 band 를
# 판별(`band_for`)하고, 개별 리포트에 적용되는 첨삭 경로(ReviewService·RuleBasedReview·
# QuizDraftService)가 band 별 상수를 쓴다. 학년을 알 수 없으면 :g56 으로 폴백해
# 기존 동작을 보존한다. 여러 학년을 섞어 집계하는 대시보드(교사/학교/NEIS)는
# band 가 애매하므로 flat 기본 상수(=5~6학년군)를 그대로 사용한다.
module ReadingDomain
  # 학년군 키·라벨. :g12=1~2학년군, :g34=3~4학년군, :g56=5~6학년군.
  BANDS = %i[g12 g34 g56].freeze
  BAND_LABELS = { g12: "1~2학년군", g34: "3~4학년군", g56: "5~6학년군" }.freeze
  DEFAULT_BAND = :g56

  # content_axis(캐시축)별 고정 문항 수(Phase 1 §1.1, A6). 표면·버전이 달라도 같은 축이면
  # 문항 수가 같아야 콘텐츠축 상한(maximum(:points_awarded)) 비교의 스케일이 일관된다.
  # 생성(QuizDraftService#normalize, Phase 2a)과 검증이 이 상수를 강제한다.
  #   mcq=객관식 문항 수 / matching=어휘↔뜻 쌍 수 / hint_reveal=힌트공개 타깃 수 / balance_vote=딜레마 수.
  CONTENT_COUNTS = { mcq: 5, matching: 5, hint_reveal: 3, balance_vote: 3 }.freeze

  # 5축 루브릭 키 (순서 고정 — 방사형 차트·가중치 계산에 사용). 학년군 무관.
  RUBRIC_AXES = %i[content emotion life structure spelling].freeze

  # 축별 한국어 라벨. 학년군 무관(축 자체는 동일, 눈높이는 성취기준·의미·프롬프트에서 분기).
  AXIS_LABELS = {
    content: "내용 이해",
    emotion: "감상 표현",
    life: "삶과 연결",
    structure: "구성·근거",
    spelling: "맞춤법"
  }.freeze

  # 학년군별 축 의미(프롬프트 축 설명·문서에 재사용).
  AXIS_MEANINGS_BY_BAND = {
    g12: {
      content: "누가 나오고 무슨 일이 있었는지(중심 내용) 파악",
      emotion: "책을 읽고 느낀 점·생각한 점을 솔직하게 표현",
      life: "책 속 인물의 마음을 나와 견주어 보기",
      structure: "생각이나 느낌을 문장으로 표현하기",
      spelling: "낱말을 소리와 다르게 바르게 쓰기"
    },
    g34: {
      content: "인물과 이야기의 흐름 파악",
      emotion: "감각적 표현을 살려 드러낸 생각과 느낌",
      life: "내 경험과 작품 속 세계를 견주어 보기",
      structure: "중심 문장·뒷받침 문장을 갖춘 문단과 고쳐쓰기",
      spelling: "문장의 짜임을 살핀 바른 문장·표기"
    },
    g56: {
      content: "인물·사건·배경 파악",
      emotion: "생각과 느낌의 구체성",
      life: "자신의 삶·경험과의 연관과 성찰(A등급 유도)",
      structure: "문장 연결·구성·고쳐쓰기",
      spelling: "표기 정확성"
    }
  }.freeze

  # 축별 2022 개정 국어 성취기준 코드(학년군별). 원문은 각 코드 옆 주석 참고.
  # 코드 근거: 교육부 고시 제2022-33호 [별책 5] 국어과 교육과정.
  ACHIEVEMENT_STANDARDS_BY_BAND = {
    g12: {
      content: "[2국02-03]",   # 글을 읽고 중심 내용을 확인한다.
      emotion: "[2국05-02]",   # 작품을 듣거나 읽으면서 느끼거나 생각한 점을 말한다.
      life: "[2국02-04]",      # 인물의 마음이나 생각을 짐작하고 이를 자신과 비교하며 글을 읽는다.
      structure: "[2국03-02]", # 쓰기에 흥미를 가지며 자신의 생각이나 느낌을 문장으로 표현한다.
      spelling: "[2국04-02]"   # 소리와 표기가 다를 수 있음을 알고 단어를 바르게 읽고 쓴다.
    },
    g34: {
      content: "[4국05-01]",   # 인물과 이야기의 흐름을 중심으로 작품을 감상한다.
      emotion: "[4국05-04]",   # 감각적 표현에 유의하여 작품을 감상하고, 감각적 표현을 활용하여 자신의 생각이나 느낌을 표현한다.
      life: "[4국05-02]",      # 자신의 경험을 바탕으로 작품 속 세계와 현실 세계를 비교하여 작품을 감상한다.
      structure: "[4국03-01]", # 중심 문장과 뒷받침 문장을 갖추어 문단을 쓰고, 문장과 문단을 중심으로 고쳐 쓴다.
      spelling: "[4국04-03]"   # 기본적인 문장의 짜임을 이해하고 적절하게 사용한다.
    },
    g56: {
      content: "[6국05-03]",   # 소설이나 극을 읽고 인물, 사건, 배경을 파악한다.
      emotion: "[6국03-03]",   # 체험한 일에 대한 감상을 나타내는 글을 쓴다.
      life: "[6국05-06]",      # 작품을 읽고 자신의 삶과 연관 지어 성찰하는 태도를 지닌다.
      structure: "[6국03-05]", # 쓰기 과정을 점검·조정하며 글을 쓰고, 글 전체를 대상으로 통일성 있게 고쳐 쓴다.
      spelling: "[6국04-06]"   # 글과 담화에 쓰인 단어 및 문장, 띄어쓰기를 민감하게 살펴 바르게 고치는 태도를 지닌다.
    }
  }.freeze

  # 축별 약점 보완 추천 활동(교사 대시보드 인사이트), 학년군별 눈높이. 가장 낮은 축 → 활동.
  RECOMMENDED_ACTIVITIES_BY_BAND = {
    g12: {
      content: "책에서 누가 나오고 무슨 일이 있었는지 한 문장으로 말해 보는 활동으로 내용을 익혀요.",
      emotion: "가장 재미있던 장면을 고르고 '왜 좋았는지'를 말해 보는 활동을 권해요.",
      life: "책 속 인물과 내가 닮은 점을 찾아 이야기해 보는 활동을 권해요.",
      structure: "생각이나 느낌을 한두 문장으로 또박또박 써 보는 연습을 권해요.",
      spelling: "소리 나는 대로 쓰기 쉬운 낱말을 바르게 고쳐 쓰는 짝 활동을 권해요."
    },
    g34: {
      content: "인물과 사건을 차례대로 간추려 보는 활동으로 내용 이해를 다져요.",
      emotion: "보고·듣고·느낀 감각적 표현을 살려 인상 깊은 장면을 쓰는 활동을 권해요.",
      life: "책 속 이야기와 내 경험을 견주어 보는 글쓰기를 권해요.",
      structure: "중심 문장과 뒷받침 문장을 갖춘 문단으로 쓰고 고쳐쓰기를 연습해요.",
      spelling: "문장의 짜임을 살펴 어색한 문장을 바르게 고치는 활동을 권해요."
    },
    g56: {
      content: "책 속 인물·사건·배경을 짚어 요약하는 활동으로 내용 이해를 다져요.",
      emotion: "인상 깊은 장면과 그 까닭을 함께 쓰는 감상 일기를 권해요.",
      life: "책 내용을 자신의 경험·생활과 연결해 보는 글쓰기를 권해요.",
      structure: "생각 그물(마인드맵)로 문단을 짜고 고쳐쓰기를 연습해요.",
      spelling: "맞춤법·띄어쓰기 짝 점검 활동으로 표기를 다듬어요."
    }
  }.freeze

  # 학년군별 프롬프트 메타(대상 라벨·어조·등급 규칙). 프롬프트 빌더가 참조.
  PROMPT_META = {
    g12: {
      grade_label: "초등학교 1~2학년",
      tone: "이제 막 글쓰기를 배우는 1~2학년입니다. 아주 쉽고 다정한 말로, 잘한 점을 먼저 크게 칭찬하고 딱 한 가지만 부드럽게 제안하세요. 어려운 낱말이나 평가 용어는 쓰지 마세요.",
      level_rule: "책 내용을 이해하고 느낀 점을 한 가지라도 솔직하게 표현하면 A, 느낌 표현이 약하고 줄거리 위주면 B, 글이 매우 짧거나 내용이 거의 없으면 C."
    },
    g34: {
      grade_label: "초등학교 3~4학년",
      tone: "글쓰기에 익숙해지는 3~4학년입니다. 쉬운 말로 칭찬과 구체적인 제안을 함께 주고, 문단 구성과 감각적 표현을 북돋우세요.",
      level_rule: "인물·사건을 이해하고 느낌이나 내 경험과의 연결이 한 가지라도 드러나면 A, 느낌은 있으나 경험 연결이 약하면 B, 줄거리 요약 위주면 C."
    },
    g56: {
      grade_label: "초등학교 5~6학년",
      tone: "맞춤법만 고치지 말고 내용·감상·삶과의 연결·구성·표기를 함께 진단하세요.",
      level_rule: "삶과 적극적으로 연결하고 성찰이 드러나면 A, 감상은 있으나 삶 연결이 약하면 B, 줄거리 요약 위주면 C."
    }
  }.freeze

  # 등급별 지급 포인트. 학년군 무관.
  LEVEL_POINTS = { "A" => 30, "B" => 20, "C" => 10 }.freeze

  # 가중치 미설정 학급용 기본값(모든 축 동일). 학년군 무관.
  DEFAULT_RUBRIC_WEIGHTS = { content: 1, emotion: 1, life: 1, structure: 1, spelling: 1 }.freeze

  # 손글씨 전사 프롬프트 — JSON {text} 강제. 학년군 무관(전사는 눈높이와 독립).
  OCR_PROMPT = <<~PROMPT.freeze
    당신은 초등학생이 손으로 쓴 독후감 사진을 정확히 전사하는 도우미입니다.
    이미지에 보이는 글자를 원문 그대로, 줄바꿈을 살려 한국어로 옮겨 적으세요.
    맞춤법이나 문장을 임의로 고치지 말고, 읽을 수 없는 글자는 물음표(?)로 표시하세요.
    반드시 아래 JSON 스키마만 반환하고 다른 설명은 붙이지 마세요.
    {"text": "전사한 본문 전체"}
  PROMPT

  # 진위·표절 의심 보조 프롬프트 — 교사 보조용, JSON {suspicion, reasons[]}. 학년군 무관.
  VERIFY_PROMPT = <<~PROMPT.freeze
    당신은 초등학생 독후감의 진위와 표절 가능성을 교사가 판단하도록 돕는 보조자입니다.
    최종 판정을 내리지 말고, 의심 정도와 근거만 제시하세요.
    suspicion 은 0.0(정상)~1.0(강한 의심) 사이의 실수로 표현하고,
    reasons 에는 그렇게 본 근거를 짧은 한국어 문장으로 담으세요.

    반드시 아래 JSON 스키마만 반환하고 다른 설명은 붙이지 마세요.
    {"suspicion": 0.0, "reasons": ["근거 문장"]}
  PROMPT

  # 학년(정수)으로 학년군 키를 판별. 미상(nil/0)·5·6 → :g56(기본, 기존 동작 보존).
  def self.band_for(grade)
    case grade.to_i
    when 1, 2 then :g12
    when 3, 4 then :g34
    else :g56
    end
  end

  # 학년군별 성취기준/추천활동 접근자. 미지원 band → 기본(:g56).
  def self.achievement_standards(band = DEFAULT_BAND)
    ACHIEVEMENT_STANDARDS_BY_BAND.fetch(band, ACHIEVEMENT_STANDARDS_BY_BAND.fetch(DEFAULT_BAND))
  end

  def self.recommended_activities(band = DEFAULT_BAND)
    RECOMMENDED_ACTIVITIES_BY_BAND.fetch(band, RECOMMENDED_ACTIVITIES_BY_BAND.fetch(DEFAULT_BAND))
  end

  # 5축 발전적 첨삭 프롬프트 빌더 — 학년군별 성취기준·눈높이·등급규칙을 주입, JSON 스키마 강제.
  def self.build_rubric_prompt(band)
    meta = PROMPT_META.fetch(band)
    codes = ACHIEVEMENT_STANDARDS_BY_BAND.fetch(band)
    meanings = AXIS_MEANINGS_BY_BAND.fetch(band)
    axis_lines = RUBRIC_AXES.map do |axis|
      "- #{axis}(#{AXIS_LABELS[axis]}, #{codes[axis]}): #{meanings[axis]}"
    end.join("\n")

    <<~PROMPT
      당신은 2022 개정 국어과 성취기준에 기반해 #{meta[:grade_label]} 학생의 독후감을 "발전적으로" 첨삭하는
      친절한 국어 선생님입니다. #{meta[:tone]}

      다음 5개 축을 각각 0~5의 정수로 채점하세요.
      #{axis_lines}

      등급 규칙: #{meta[:level_rule]} 포인트는 A=30, B=20, C=10.

      반드시 아래 JSON 스키마만 반환하고 다른 텍스트는 붙이지 마세요.
      {
        "level": "A|B|C",
        "rubric": { "content": 0, "emotion": 0, "life": 0, "structure": 0, "spelling": 0 },
        "praise": ["잘한 점 문장"],
        "fix": ["보완하면 좋을 점 문장"],
        "grow": [ { "text": "성장 제안 문장", "standard_code": "#{codes[:life]}" } ],
        "pts": 0
      }
    PROMPT
  end

  # 독서 퀴즈 초안 생성 프롬프트 빌더 — 학년군 라벨만 눈높이로 반영(P5.6). JSON {questions:[...]} 강제.
  def self.build_quizgen_prompt(band)
    label = PROMPT_META.fetch(band)[:grade_label]
    <<~PROMPT
      당신은 #{label} 학생이 읽은 책으로 4지선다 독서 퀴즈를 만드는 국어 선생님입니다.
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
  end

  # content_axis(캐시축)별 게임 콘텐츠 생성 프롬프트 빌더(Phase 2a). build_quizgen_prompt(mcq 4지선다)의
  # 일반화 — 4개 content_axis(mcq/matching/hint_reveal/balance_vote)를 모두 덮는다. 주입 요소:
  # (a) band 성취기준·눈높이(ACHIEVEMENT_STANDARDS_BY_BAND·PROMPT_META), (b) 난이도 티어,
  # (c) 오답 품질(그럴듯하나 분명히 틀림·상호배타·비슷한 길이), (d) 해설 강제, (e) 중복 방지(항목별 다른 초점),
  # (f) count 강제(CONTENT_COUNTS 참조), (g) 근거 한정·환각 억제(줄거리에 없는 사실 금지, 빈약하면 일반 독해),
  # (h) content_axis별 JSON 스키마. QuizDraftService(AI 경로)가 system_instruction 으로 사용한다.
  def self.build_content_prompt(band, content_axis)
    meta  = PROMPT_META.fetch(band, PROMPT_META.fetch(DEFAULT_BAND))
    codes = ACHIEVEMENT_STANDARDS_BY_BAND.fetch(band, ACHIEVEMENT_STANDARDS_BY_BAND.fetch(DEFAULT_BAND))
    count = CONTENT_COUNTS.fetch(content_axis.to_sym)
    label = meta[:grade_label]

    intro = <<~HEAD
      당신은 #{label} 학생이 읽은 책으로 독서 게임 콘텐츠를 만드는 국어 선생님입니다.
      2022 개정 국어과 성취기준 #{codes[:content]}(내용 이해)에 맞춰 #{label} 눈높이로 출제하세요. #{meta[:tone]}

      공통 규칙:
      - 반드시 정확히 #{count}개를 만드세요(더도 덜도 안 됩니다).
      - 난이도(difficulty)는 1(쉬움)~3(어려움) 사이 정수로 표시하세요.
      - 각 항목에는 정답 근거를 알려 주는 해설(explanation)을 반드시 넣으세요.
      - 오답(distractor)은 그럴듯하지만 분명히 틀리도록, 서로 겹치지 않게, 정답과 길이를 비슷하게 만드세요.
      - 항목끼리 초점이 겹치지 않도록 서로 다른 내용을 물어 중복을 피하세요.
      - 책의 제목·지은이·줄거리에 없는 사실을 지어내지 마세요. 줄거리 정보가 빈약하면 일반적인 독서·독해 능력을 묻는 문항으로 대체하세요.
    HEAD

    intro + "\n" + content_axis_schema(content_axis.to_sym, count)
  end

  # content_axis별 JSON 스키마 지시(build_content_prompt 보조). 각 축의 스키마 키·형식을 고정한다.
  def self.content_axis_schema(content_axis, count)
    case content_axis
    when :mcq
      <<~MCQ
        [객관식(mcq)] 4지선다 문항을 만드세요. 보기(choices)는 4개, 정답은 하나만(answer_index) 되도록 구성하세요.
        반드시 아래 JSON 스키마만 반환하고 다른 설명은 붙이지 마세요.
        {
          "questions": [
            { "prompt": "문항 질문", "choices": ["보기1", "보기2", "보기3", "보기4"], "answer_index": 0, "explanation": "정답 해설", "difficulty": 1 }
          ]
        }
      MCQ
    when :matching
      <<~MATCH
        [짝짓기(matching)] 어휘와 그 뜻을 잇는 #{count}개의 쌍(word↔meaning)을 만드세요.
        각 뜻(meaning)은 서로 명확히 구분되어 오답 혼동 없이 정답 쌍이 하나로 정해지게 하세요.
        반드시 아래 JSON 스키마만 반환하고 다른 설명은 붙이지 마세요.
        {
          "pairs": [ { "word": "어휘", "meaning": "그 어휘의 뜻" } ],
          "explanation": "짝을 이루는 기준 해설",
          "difficulty": 1
        }
      MATCH
    when :hint_reveal
      <<~HINT
        [힌트 공개(hint_reveal)] #{count}개의 타깃(정답, answer)을 정하고, 각 타깃마다 힌트를 여러 개 만드세요.
        힌트(hints)는 가장 어려운 것부터 가장 쉬운 것 순서로 배열하고, 타깃을 직접 말하지 말고 점점 좁혀 주세요.
        틀린 오답 힌트는 넣지 마세요.
        반드시 아래 JSON 스키마만 반환하고 다른 설명은 붙이지 마세요.
        {
          "targets": [
            { "answer": "타깃 정답", "hints": ["가장 어려운 힌트", "...", "가장 쉬운 힌트"], "explanation": "타깃 해설", "difficulty": 1 }
          ]
        }
      HINT
    when :balance_vote
      <<~BAL
        [밸런스 투표(balance_vote)] 정답이 없는 딜레마 #{count}개를 만드세요.
        각 딜레마는 두 개의 선택지(options)를 두되, 정답이 없으므로 오답을 표시하지 말고 두 선택지 모두 그럴듯하게 만드세요.
        반드시 아래 JSON 스키마만 반환하고 다른 설명은 붙이지 마세요.
        {
          "dilemmas": [
            { "prompt": "딜레마 질문", "options": ["선택지1", "선택지2"], "explanation": "왜 정답이 없는지 안내" }
          ]
        }
      BAL
    else
      raise ArgumentError, "지원하지 않는 content_axis: #{content_axis.inspect}"
    end
  end

  # 학년군별 프롬프트를 로드 시점에 1회 빌드해 동결(요청마다 재생성하지 않음).
  RUBRIC_PROMPTS = BANDS.index_with { |band| build_rubric_prompt(band).freeze }.freeze
  QUIZGEN_PROMPTS = BANDS.index_with { |band| build_quizgen_prompt(band).freeze }.freeze

  # (band × content_axis) 콘텐츠 프롬프트를 사전빌드·동결(Phase 2a). content_axis 는 CONTENT_COUNTS 의 4값.
  CONTENT_PROMPTS = BANDS.index_with do |band|
    CONTENT_COUNTS.keys.index_with { |axis| build_content_prompt(band, axis).freeze }.freeze
  end.freeze

  def self.rubric_prompt(band = DEFAULT_BAND)
    RUBRIC_PROMPTS.fetch(band, RUBRIC_PROMPTS.fetch(DEFAULT_BAND))
  end

  def self.quizgen_prompt(band = DEFAULT_BAND)
    QUIZGEN_PROMPTS.fetch(band, QUIZGEN_PROMPTS.fetch(DEFAULT_BAND))
  end

  # content_axis 콘텐츠 프롬프트 접근자. 미지원 band/axis → 기본(g56 / mcq)으로 폴백.
  def self.content_prompt(band = DEFAULT_BAND, content_axis = :mcq)
    by_band = CONTENT_PROMPTS.fetch(band, CONTENT_PROMPTS.fetch(DEFAULT_BAND))
    by_band.fetch(content_axis.to_sym, by_band.fetch(:mcq))
  end

  # ── 하위호환 flat 상수(=5~6학년군 기본). 여러 학년을 섞어 집계하는 대시보드
  #    (교사/학교/NEIS)와 기존 참조·테스트가 학년군 인자 없이 그대로 쓴다.
  ACHIEVEMENT_STANDARDS = ACHIEVEMENT_STANDARDS_BY_BAND.fetch(DEFAULT_BAND)
  RECOMMENDED_ACTIVITIES = RECOMMENDED_ACTIVITIES_BY_BAND.fetch(DEFAULT_BAND)
  RUBRIC_PROMPT = RUBRIC_PROMPTS.fetch(DEFAULT_BAND)
  QUIZGEN_PROMPT = QUIZGEN_PROMPTS.fetch(DEFAULT_BAND)
end
