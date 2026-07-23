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

  # 학년군 → 정보나루(data4library) 인기대출 연령대 코드. "이 책은 어때요?" 발견 섹션이
  # 학년군에 맞는 인기도서를 조회할 때 loanItemSrch 의 age 파라미터로 넘긴다.
  # 값은 몬스터 스프라이트 빌드스크립트 BANDS 매핑과 일치(a8=8세·a10=10세·a12=12세).
  AGE_CODE_BY_BAND = { g12: "a8", g34: "a10", g56: "a12" }.freeze

  # content_axis(캐시축)별 고정 문항 수(Phase 1 §1.1, A6). 표면·버전이 달라도 같은 축이면
  # 문항 수가 같아야 콘텐츠축 상한(maximum(:points_awarded)) 비교의 스케일이 일관된다.
  # 생성(QuizDraftService#normalize, Phase 2a)과 검증이 이 상수를 강제한다.
  #   mcq=객관식 문항 수 / hint_reveal=힌트공개 타깃 수.
  # 게임 재구성 Phase 1: matching(vocab) 생성 경로 제거 — 이 상수에서 matching 을 빼면 warm!·
  # CONTENT_PROMPTS·QuizDraft0 가 matching 을 더는 생성/사전빌드하지 않는다. Quiz#content_axis enum
  # 의 matching 값은 과거 기록·스코어러 보존차 유지(휴면)하되 생성은 안 한다.
  CONTENT_COUNTS = { mcq: 5, hint_reveal: 3 }.freeze

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

  # 축별 2022 개정 국어 성취기준 "대표" 코드(학년군별). 5축 각각에 가장 잘 맞는 대표 코드 1개다.
  # 원문은 각 코드 옆 주석 참고. 코드 근거: 교육부 고시 제2022-33호 [별책 5] 국어과 교육과정.
  # 학년군별 성취기준 "전체" 목록은 CURRICULUM_STANDARDS_BY_BAND(첨삭 프롬프트 allowlist) 참고.
  # 여기의 5개 대표 코드는 반드시 CURRICULUM_STANDARDS_BY_BAND 목록의 부분집합이어야 한다.
  ACHIEVEMENT_STANDARDS_BY_BAND = {
    g12: {
      content: "[2국02-03]",   # 글을 읽고 중심 내용을 확인한다.
      emotion: "[2국05-02]",   # 작품을 듣거나 읽으면서 느끼거나 생각한 점을 말한다.
      life: "[2국02-04]",      # 인물의 마음이나 생각을 짐작하고 이를 자신과 비교하며 글을 읽는다.
      structure: "[2국03-02]", # 쓰기에 흥미를 가지며 자신의 생각이나 느낌을 문장으로 표현한다.
      spelling: "[2국04-02]"   # 소리와 표기가 다를 수 있음을 알고 단어를 바르게 읽고 쓴다.
    },
    g34: {
      content: "[4국05-02]",   # 인물의 성격과 역할을 파악하며 작품을 감상한다.
      emotion: "[4국05-04]",   # 감각적 표현을 활용하여 자신의 생각이나 느낌을 표현한다.
      life: "[4국05-01]",      # 자신의 경험을 바탕으로 작품을 읽는다.
      structure: "[4국03-01]", # 중심 문장과 뒷받침 문장을 갖추어 문단을 쓰고, 문장과 문단을 중심으로 고쳐 쓴다.
      spelling: "[4국04-03]"   # 기본적인 문장의 짜임을 이해하고 적절하게 사용한다.
    },
    g56: {
      content: "[6국05-03]",   # 소설이나 극을 읽고 인물, 사건, 배경을 파악한다.
      emotion: "[6국03-03]",   # 체험한 일에 대한 감상을 나타내는 글을 쓴다.
      life: "[6국05-06]",      # 문학을 통해 자신과 삶을 성찰한다.
      structure: "[6국03-05]", # 쓰기 과정을 점검·조정하며 글을 쓰고, 글 전체를 대상으로 통일성 있게 고쳐 쓴다.
      spelling: "[6국04-04]"   # 문장 성분의 호응을 이해하고 적절하게 표현한다.
    }
  }.freeze

  # 학년군별 국어 성취기준 "전체" 목록(2022 개정, 교육부 고시 제2022-33호 [별책 5]).
  # 출처: app/views/monsters/성취기준.md. 독후감 첨삭과 직접 관련된 읽기(02)·쓰기(03)·
  # 문법(04)·문학(05) 영역만 담는다(듣기·말하기(01)·매체(06)는 독후감 첨삭과 무관해 제외).
  # 첨삭 프롬프트(build_rubric_prompt)가 "이 목록의 코드만 인용하라"는 하드 제약의
  # 근거(allowlist)로 주입해, LLM 이 상위 학년 성취기준을 학생에게 요구하지 못하게 막는다.
  CURRICULUM_STANDARDS_BY_BAND = {
    g12: {
      "읽기" => [
        [ "[2국02-01]", "글자, 단어, 문장, 짧은 글을 정확하게 소리 내어 읽는다." ],
        [ "[2국02-02]", "의미가 잘 드러나도록 문장과 짧은 글을 알맞게 띄어 읽는다." ],
        [ "[2국02-03]", "글을 읽고 중심 내용을 확인한다." ],
        [ "[2국02-04]", "인물의 마음이나 생각을 짐작하고 이를 자신과 비교하며 글을 읽는다." ],
        [ "[2국02-05]", "읽기에 흥미를 가지고 즐겨 읽는 태도를 지닌다." ]
      ],
      "쓰기" => [
        [ "[2국03-01]", "글자와 단어를 바르게 쓴다." ],
        [ "[2국03-02]", "쓰기에 흥미를 가지며 자신의 생각이나 느낌을 문장으로 표현한다." ],
        [ "[2국03-03]", "주변 소재에 대해 소개하는 글을 쓴다." ],
        [ "[2국03-04]", "겪은 일을 표현하는 글을 자유롭게 쓰고, 쓴 글을 함께 읽고 생각이나 느낌을 나눈다." ]
      ],
      "문법" => [
        [ "[2국04-01]", "한글 자모의 이름과 소릿값을 알고 정확하게 발음하고 쓴다." ],
        [ "[2국04-02]", "소리와 표기가 다를 수 있음을 알고 단어를 바르게 읽고 쓴다." ],
        [ "[2국04-03]", "문장과 문장 부호를 알맞게 쓰고 한글에 호기심을 가진다." ]
      ],
      "문학" => [
        [ "[2국05-01]", "말놀이, 낭송 등을 통해 말의 재미와 즐거움을 느낀다." ],
        [ "[2국05-02]", "작품을 듣거나 읽으면서 느끼거나 생각한 점을 말한다." ],
        [ "[2국05-03]", "작품 속 인물의 모습, 행동, 마음을 상상하여 시, 노래, 이야기, 그림 등으로 표현한다." ],
        [ "[2국05-04]", "시나 노래, 이야기에 흥미를 가진다." ]
      ]
    },
    g34: {
      "읽기" => [
        [ "[4국02-01]", "글의 의미를 파악하며 유창하게 글을 읽는다." ],
        [ "[4국02-02]", "문단과 글에서 중심 생각을 파악하고 내용을 간추린다." ],
        [ "[4국02-03]", "질문을 활용하여 글을 예측하며 읽고 자신의 읽기 과정을 점검한다." ],
        [ "[4국02-04]", "글에 나타난 사실과 의견을 구분하고 필자와 자신의 의견을 비교한다." ],
        [ "[4국02-05]", "글이나 자료의 출처가 믿을 만한지 판단한다." ],
        [ "[4국02-06]", "읽기에 대한 효능감을 가지고 독서한다." ]
      ],
      "쓰기" => [
        [ "[4국03-01]", "중심 문장과 뒷받침 문장을 갖추어 문단을 쓰고, 문장과 문단을 중심으로 고쳐 쓴다." ],
        [ "[4국03-02]", "이유를 들어 의견을 제시하는 글을 쓴다." ],
        [ "[4국03-03]", "독자에게 마음을 전하는 글을 쓴다." ],
        [ "[4국03-04]", "목적과 주제를 고려하여 내용을 생성하고 정확하게 표현한다." ],
        [ "[4국03-05]", "쓰기에 대한 효능감을 가지고 글을 쓴다." ]
      ],
      "문법" => [
        [ "[4국04-01]", "단어와 단어 간의 의미 관계를 파악한다." ],
        [ "[4국04-02]", "단어를 분류하고 국어사전을 활용하여 능동적인 국어 활동을 한다." ],
        [ "[4국04-03]", "기본적인 문장의 짜임을 이해하고 적절하게 사용한다." ],
        [ "[4국04-04]", "글과 담화에 쓰인 높임 표현과 지시·접속 표현을 이해하고 상황에 맞게 표현한다." ],
        [ "[4국04-05]", "언어가 의사소통과 관계 형성의 수단임을 이해하고 국어를 소중히 여기는 태도를 지닌다." ]
      ],
      "문학" => [
        [ "[4국05-01]", "자신의 경험을 바탕으로 작품을 읽는다." ],
        [ "[4국05-02]", "인물의 성격과 역할을 파악하며 작품을 감상한다." ],
        [ "[4국05-03]", "인상적인 부분을 중심으로 작품에 대한 의견을 나눈다." ],
        [ "[4국05-04]", "감각적 표현을 활용하여 자신의 생각이나 느낌을 표현한다." ],
        [ "[4국05-05]", "작품을 감상하는 즐거움을 느낀다." ]
      ]
    },
    g56: {
      "읽기" => [
        [ "[6국02-01]", "글의 구조를 고려하며 주제나 주장을 파악하고 글 내용을 요약한다." ],
        [ "[6국02-02]", "생략된 내용과 함축된 의미를 추론한다." ],
        [ "[6국02-03]", "설명 방법과 논증 방법의 적절성을 판단한다." ],
        [ "[6국02-04]", "다양한 글이나 자료를 읽고 문제를 해결한다." ],
        [ "[6국02-05]", "읽기에 적극적으로 참여하고 읽기 과정을 성찰한다." ]
      ],
      "쓰기" => [
        [ "[6국03-01]", "알맞은 내용을 선정하여 대상의 특성이 나타나게 설명하는 글을 쓴다." ],
        [ "[6국03-02]", "적절한 근거를 사용하고 인용의 출처를 밝히며 주장하는 글을 쓴다." ],
        [ "[6국03-03]", "체험한 일에 대한 감상을 나타내는 글을 쓴다." ],
        [ "[6국03-04]", "독자와 매체를 고려하여 내용을 생성하고 표현하며 글을 쓴다." ],
        [ "[6국03-05]", "쓰기 과정을 점검·조정하며 글을 쓰고, 글 전체를 대상으로 통일성 있게 고쳐 쓴다." ],
        [ "[6국03-06]", "쓰기 윤리를 지키며 글을 쓰고 성찰한다." ]
      ],
      "문법" => [
        [ "[6국04-01]", "지역에 따른 언어와 표준어를 이해한다." ],
        [ "[6국04-02]", "글과 담화에 쓰인 높임 표현과 시간 표현을 이해하고 적절하게 사용한다." ],
        [ "[6국04-03]", "고유어와 관용 표현의 특성을 이해하고 적절하게 사용한다." ],
        [ "[6국04-04]", "문장 성분의 호응을 이해하고 적절하게 표현한다." ],
        [ "[6국04-05]", "국어생활을 점검하고 개선하려는 태도를 지닌다." ]
      ],
      "문학" => [
        [ "[6국05-01]", "작가의 의도를 생각하며 작품을 읽는다." ],
        [ "[6국05-02]", "비유적 표현의 효과에 유의하여 작품을 감상한다." ],
        [ "[6국05-03]", "소설이나 극을 읽고 인물, 사건, 배경을 파악한다." ],
        [ "[6국05-04]", "다양한 해석을 비교하며 작품을 이해한다." ],
        [ "[6국05-05]", "갈래의 특성에 맞게 작품을 표현한다." ],
        [ "[6국05-06]", "문학을 통해 자신과 삶을 성찰한다." ]
      ]
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

  # 학년군별 안내형(가이드) 독후감 작성 문항. 학생이 빈 화면 앞에서 막히지 않도록 5축(RUBRIC_AXES)을
  # 처음(intro)-가운데(body)-끝(conclusion) 흐름의 질문으로 풀어 준다. 문항 수·part 구성은 눈높이별로
  # 다르다(g12=5 / g34=7 / g56=8). 각 문항은 축(axis)·위치(part)·질문(question)·힌트(hint)·예시(example)를
  # 담고, ratio_hint(줄거리:생각 비율 안내)·spelling_tip(맞춤법 점검 안내)이 밴드별로 붙는다.
  # 뷰(reports/new)가 `@guided[:questions].each` 로 소비한다(외부 API 무관·정적 상수).
  GUIDED_QUESTIONS_BY_BAND = {
    g56: {
      questions: [
        { axis: :content, part: :intro,
          question: "이 책을 왜 읽게 되었나요? 제목·표지를 보고 어떤 생각이 들었나요?",
          hint: "읽게 된 이유와 기대를 2~3문장으로 써 봐요.",
          example: "저는 동물을 좋아해서 이 책을 읽게 되었습니다. 제목을 보고 재미있는 이야기일 것 같아 기대되었어요." },
        { axis: :content, part: :body,
          question: "가장 기억에 남는 장면은 무엇인가요? (줄거리는 짧게!)",
          hint: "줄거리는 2~3문장만 써요.",
          example: "주인공이 친구를 끝까지 도와주는 장면이 기억에 남았습니다." },
        { axis: :emotion, part: :body,
          question: "그 장면이 왜 기억에 남았나요? 어떤 생각·느낌이 들었나요?",
          hint: "여기는 길게! 왜 그렇게 느꼈는지 써 봐요.",
          example: "저도 친구가 어려울 때 도와준 적이 있어서 더욱 공감되었습니다." },
        { axis: :emotion, part: :body,
          question: "가장 슬프거나 놀라웠던 부분은 무엇이었나요? 왜 그렇게 느꼈나요?",
          hint: "마음이 크게 움직인 장면을 떠올려 봐요.",
          example: "주인공이 혼자 남겨지는 장면이 가장 슬펐습니다. 외로움이 느껴졌기 때문입니다." },
        { axis: :life, part: :body,
          question: "내가 주인공이라면 어떻게 했을까요? 나의 경험과 비슷한 일이 있었나요?",
          hint: "'나라면?'과 내 경험을 상상해서 써 봐요.",
          example: "나라면 조금 더 용기를 내어 먼저 도와주었을 것 같습니다. 저도 전학 온 친구를 도운 적이 있어요." },
        { axis: :life, part: :body,
          question: "주인공(또는 등장인물)에게 해 주고 싶은 말이 있나요?",
          hint: "응원이나 조언을 한마디 써 봐요.",
          example: "포기하지 않아서 정말 멋지다고 말해 주고 싶습니다." },
        { axis: :life, part: :conclusion,
          question: "이 책을 읽고 무엇을 느끼거나 배웠나요? 실천하고 싶은 점이 있나요?",
          hint: "배운 점과 다짐을 써 봐요.",
          example: "친구를 배려하는 마음이 얼마나 중요한지 알게 되었습니다. 앞으로 먼저 도와주고 싶습니다." },
        { axis: :structure, part: :conclusion,
          question: "친구들에게 추천한다면 왜 추천하고 싶나요? 별점(★)과 한 줄 평도 남겨 볼까요?",
          hint: "추천 이유와 별점, 한 줄 평을 써 봐요.",
          example: "★★★★★ 우정의 소중함을 배울 수 있어 친구들에게 추천합니다." }
      ],
      ratio_hint: "줄거리는 20~30%만, 내 생각·느낌은 70~80%! 처음-가운데-끝 순서로 이어 써요.",
      spelling_tip: "다 썼으면 맞춤법과 띄어쓰기를 한 번 더 살펴봐요."
    },
    g34: {
      questions: [
        { axis: :content, part: :intro,
          question: "이 책을 왜 읽고 싶었어요?",
          hint: "읽고 싶었던 까닭을 써 봐요.",
          example: "표지에 강아지가 있어서 읽고 싶었어요." },
        { axis: :content, part: :body,
          question: "가장 기억에 남는(재미있던) 장면은 무엇이에요? (줄거리는 짧게)",
          hint: "줄거리는 짧게 써요.",
          example: "친구를 도와주는 장면이 기억에 남아요." },
        { axis: :emotion, part: :body,
          question: "그 장면에서 어떤 느낌이 들었어요? 왜 그렇게 느꼈어요?",
          hint: "느낌을 자세히 써 봐요.",
          example: "따뜻한 마음이 들었어요. 저도 도움받은 적이 있거든요." },
        { axis: :emotion, part: :body,
          question: "가장 슬프거나 놀라웠던 부분은 무엇이에요?",
          hint: "마음이 움직인 장면을 써요.",
          example: "주인공이 길을 잃는 부분이 놀라웠어요." },
        { axis: :life, part: :body,
          question: "내가 주인공이라면 어떻게 했을까요?",
          hint: "'나라면?'을 상상해 봐요.",
          example: "나라면 어른에게 도와달라고 했을 거예요." },
        { axis: :life, part: :conclusion,
          question: "책을 읽고 무엇을 느끼거나 알게 됐어요?",
          hint: "느낀 점·알게 된 점을 써요.",
          example: "친구를 도우면 나도 기쁘다는 걸 알았어요." },
        { axis: :content, part: :conclusion,
          question: "친구에게 추천하고 싶어요? 왜요?",
          hint: "추천 이유를 써 봐요.",
          example: "재미있고 따뜻해서 추천하고 싶어요." }
      ],
      ratio_hint: "줄거리는 짧게, 내 생각·느낌을 더 많이 써 봐요!",
      spelling_tip: "문장이 어색하지 않은지 다시 읽어 봐요."
    },
    g12: {
      questions: [
        { axis: :content, part: :intro,
          question: "무슨 책을 읽었어요? 왜 골랐어요?",
          hint: "고른 까닭을 써 봐요.",
          example: "동물 책이라서 골랐어요." },
        { axis: :content, part: :body,
          question: "가장 재미있던 부분은 무엇이에요?",
          hint: "재미있던 장면을 써요.",
          example: "강아지가 뛰어노는 부분이요." },
        { axis: :emotion, part: :body,
          question: "그때 어떤 마음이 들었어요? (재미있어요/슬퍼요/기뻐요)",
          hint: "마음을 써 봐요.",
          example: "너무 재미있고 기뻤어요." },
        { axis: :life, part: :conclusion,
          question: "책을 읽고 무슨 생각을 했어요?",
          hint: "든 생각을 써요.",
          example: "나도 강아지를 키우고 싶어요." },
        { axis: :content, part: :conclusion,
          question: "친구에게 이 책 이야기를 해 주고 싶어요? 왜요?",
          hint: "이유를 써 봐요.",
          example: "재미있으니까 친구도 봤으면 좋겠어요." }
      ],
      ratio_hint: "줄거리보다 내 마음을 더 많이 써 봐요!",
      spelling_tip: "소리 나는 대로 쓴 낱말이 없는지 봐요."
    }
  }.freeze

  # 손글씨 전사 프롬프트 — JSON {text} 강제. 학년군 무관(전사는 눈높이와 독립).
  OCR_PROMPT = <<~PROMPT.freeze
    당신은 초등학생이 손으로 쓴 독후감 사진을 정확히 전사하는 도우미입니다.
    이미지의 글자를 원문 그대로 한국어로 옮겨 적습니다. 이때 가장 중요한 일은 학생이 "일부러 나눈 문단"을 그대로 살리는 것입니다.

    [문단 구분 — 반드시 지킬 것]
    - 원고지나 줄공책은 줄이 종이 오른쪽 끝에 닿으면 저절로 다음 줄로 넘어갑니다. 이렇게 종이 폭 때문에 생긴 행 끝 줄바꿈은 문단 구분이 아니므로 없애고, 한 문단은 끊김 없이 이어서 씁니다.
    - 다음 신호 중 하나라도 보이면 학생이 "새 문단을 일부러 시작"한 것이니 반드시 문단을 나눕니다.
      · 줄 첫머리를 한두 칸 비우고 들여쓰기해서 시작한 줄 (가장 흔한 신호이니 특히 주의)
      · 앞 줄이 오른쪽 끝에 한참 못 미쳐 끝났는데, 다음 줄에서 새로운 내용이 시작될 때
      · 중간에 빈 줄이 있을 때
    - 맨 윗줄에 있는 글의 제목은 그 자체로 하나의 독립된 문단입니다.
    - 문단이 나뉘는 자리에는 JSON 문자열에서 빈 줄 하나(\\n\\n)를 넣어 문단을 확실히 구분하고, 한 문단 안에서는 줄바꿈 없이 이어 씁니다.

    [전사 규칙]
    - 행 사이에서 한 단어가 갈라졌다면 공백 없이 붙이고(예: "조각상"과 "을"이 두 줄에 갈라졌으면 "조각상을"), 문장이나 단어 사이라면 필요한 공백을 넣어 이어 씁니다.
    - 맞춤법이나 문장을 임의로 고치지 말고, 읽을 수 없는 글자는 물음표(?)로 표시하세요.

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

  # 온디맨드 **게임 플레이** 전용 밴드 판별. band_for 와 달리 학년 미상(nil/0)을 기본 최고
  # 학년군(:g56)이 아니라 **최저 학년군(:g12)** 으로 고정한다. 학급/학년이 없는 학생에게
  # 5~6학년 콘텐츠를 자동 매칭하면 ① 눈높이에 안 맞는 어려운 콘텐츠가 노출되고, ② 밴드 경계
  # (QuizPolicy#within_band?)가 사실상 "학년 미상 = 최고 밴드 통과"로 느슨해진다. 명시된 학년은
  # band_for 와 동일하게 매핑한다. 리졸버(ContentProvider)와 정책(QuizPolicy)이 같은 함수를 써야
  # 생성 밴드와 인가 밴드가 일치한다. 5축 첨삭·다학년 대시보드는 기존대로 band_for(g56 폴백)를 쓴다
  # (대상 학생은 학급이 있어 무영향).
  def self.game_band_for(grade)
    grade.to_i.zero? ? :g12 : band_for(grade)
  end

  # 안내형 독후감 작성용 밴드 판별. game_band_for 와 동형으로 학년 미상(nil/0/blank)을 **최저
  # 밴드(:g12)** 로 고정한다(age-safety — 학급/학년이 없는 학생에게 어려운 5~6학년 문항을 기본
  # 노출하지 않기 위함). 첨삭·대시보드용 band_for(g56 폴백)와 목적이 달라 guided 전용으로 둔다.
  def self.guided_band_for(grade)
    grade.to_i.zero? ? :g12 : band_for(grade)
  end

  # 발견("이 책은 어때요?") 밴드 판별. 아동 대면 콘텐츠라 game_band_for/guided_band_for 와
  # 동일 규칙 — 학급 없는 학생(nil/0)을 최저 학년군(:g12)으로 고정해 5~6학년 인기책 기본
  # 노출을 막는다. 명시된 학년은 band_for 와 동일하게 매핑한다.
  def self.discovery_band_for(grade)
    grade.to_i.zero? ? :g12 : band_for(grade)
  end

  # 밴드별 안내형 작성 문항 Hash 접근자. 미지원 band → :g56 폴백으로 항상 non-empty Hash 반환.
  def self.guided_questions(band)
    GUIDED_QUESTIONS_BY_BAND.fetch(band, GUIDED_QUESTIONS_BY_BAND[:g56])
  end

  # 학년군별 성취기준/추천활동 접근자. 미지원 band → 기본(:g56).
  def self.achievement_standards(band = DEFAULT_BAND)
    ACHIEVEMENT_STANDARDS_BY_BAND.fetch(band, ACHIEVEMENT_STANDARDS_BY_BAND.fetch(DEFAULT_BAND))
  end

  def self.recommended_activities(band = DEFAULT_BAND)
    RECOMMENDED_ACTIVITIES_BY_BAND.fetch(band, RECOMMENDED_ACTIVITIES_BY_BAND.fetch(DEFAULT_BAND))
  end

  # 학년군별 성취기준 allowlist 블록(첨삭 프롬프트 주입용). 영역(읽기·쓰기·문법·문학)별로
  # 묶어 "  - [코드] 설명" 목록 문자열로 만든다. 미지원 band → :g56 폴백.
  def self.build_standards_allowlist(band)
    domains = CURRICULUM_STANDARDS_BY_BAND.fetch(band, CURRICULUM_STANDARDS_BY_BAND.fetch(DEFAULT_BAND))
    domains.map do |domain, entries|
      lines = entries.map { |code, desc| "  - #{code} #{desc}" }.join("\n")
      "#{domain}\n#{lines}"
    end.join("\n")
  end

  # 5축 발전적 첨삭 프롬프트 빌더 — 학년군별 성취기준·눈높이·등급규칙을 주입, JSON 스키마 강제.
  # **학년 눈높이 봉쇄(핵심)**: 학년군 성취기준 전체 목록(allowlist)을 함께 주입하고, 이 목록 밖의
  # 성취기준(특히 상위 학년 코드)으로는 수정을 요구하지 못하도록 하드 제약을 건다. 예) 3학년 학생에게
  # 6학년 성취기준을 근거로 첨삭하는 문제를 원천 차단한다.
  def self.build_rubric_prompt(band)
    meta = PROMPT_META.fetch(band)
    codes = ACHIEVEMENT_STANDARDS_BY_BAND.fetch(band)
    meanings = AXIS_MEANINGS_BY_BAND.fetch(band)
    band_label = BAND_LABELS.fetch(band)
    allowlist = build_standards_allowlist(band)
    axis_lines = RUBRIC_AXES.map do |axis|
      "- #{axis}(#{AXIS_LABELS[axis]}, #{codes[axis]}): #{meanings[axis]}"
    end.join("\n")

    <<~PROMPT
      당신은 2022 개정 국어과 성취기준에 기반해 #{meta[:grade_label]} 학생의 독후감을 "발전적으로" 첨삭하는
      친절한 국어 선생님입니다. #{meta[:tone]}

      [매우 중요 — 학년 눈높이와 성취기준 사용 규칙]
      - 이 학생은 #{meta[:grade_label]}(#{band_label})입니다. 칭찬·보완·성장 제안(praise·fix·grow)과
        standard_code 는 반드시 아래 "#{band_label} 국어 성취기준" 목록 안의 코드만 사용하세요.
      - 다른 학년군의 성취기준, 특히 이 학생보다 높은 학년에서 배우는 내용을 근거로 수정을 요구하지 마세요.
        목록에 없는 코드는 절대 쓰지 말고, 목록에 없는 상위 학년 수준의 기술(예: 논증·비유 해석·주장하는 글
        등 이 학년군에서 다루지 않는 내용)을 요구하지 마세요.
      - 이 학년군에서 기대하는 수준 안에서만 진단하고, 학생 눈높이를 넘어서는 것을 지적하지 마세요.

      [#{band_label} 국어 성취기준 — 아래 목록 안에서만 인용]
      #{allowlist}

      다음 5개 축을 각각 0~5의 정수로 채점하세요.
      #{axis_lines}

      등급 규칙: #{meta[:level_rule]} 포인트는 A=30, B=20, C=10.

      반드시 아래 JSON 스키마만 반환하고 다른 텍스트는 붙이지 마세요.
      grow[].standard_code 에는 반드시 위 "#{band_label} 국어 성취기준" 목록의 코드 중 하나만 넣으세요.
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
  # 일반화 — content_axis(mcq/hint_reveal)를 덮는다(게임 재구성 Phase 1: matching 생성 경로 제거). 주입 요소:
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
    else
      raise ArgumentError, "지원하지 않는 content_axis: #{content_axis.inspect}"
    end
  end

  # 학년군별 성취기준 allowlist 블록을 로드 시점에 1회 빌드해 동결.
  STANDARDS_ALLOWLISTS = BANDS.index_with { |band| build_standards_allowlist(band).freeze }.freeze

  def self.standards_allowlist(band = DEFAULT_BAND)
    STANDARDS_ALLOWLISTS.fetch(band, STANDARDS_ALLOWLISTS.fetch(DEFAULT_BAND))
  end

  # 학년군별 프롬프트를 로드 시점에 1회 빌드해 동결(요청마다 재생성하지 않음).
  RUBRIC_PROMPTS = BANDS.index_with { |band| build_rubric_prompt(band).freeze }.freeze
  QUIZGEN_PROMPTS = BANDS.index_with { |band| build_quizgen_prompt(band).freeze }.freeze

  # (band × content_axis) 콘텐츠 프롬프트를 사전빌드·동결(Phase 2a). content_axis 는 CONTENT_COUNTS 의 값(mcq·hint_reveal).
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
