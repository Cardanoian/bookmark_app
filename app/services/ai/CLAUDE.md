# app/services/ai — Google Gemini 연동 AI 서비스

독서교육 5축 첨삭·손글씨 OCR·퀴즈 초안 생성·진위(표절) 확인을 담당하는 AI 서비스 계층. 공통 HTTP 게이트웨이 `GeminiClient` 를 통해 `generateContent` 를 호출하며, API 키(`credentials.gemini.api_key`)가 없거나 호출이 실패하면 각 서비스가 규칙기반/오프라인/중립값으로 폴백한다(OCR만 예외 — 폴백 없이 기능 비활성화). 모든 프롬프트·루브릭 상수는 `ReadingDomain` 에 있다. **루브릭 첨삭·퀴즈 초안은 학생 학급 학년으로 학년군(g12/g34/g56)을 판별해 성취기준·눈높이 프롬프트를 분기**한다(`ReviewService`→`report.grade_band_key`, `QuizDraftService`→학급 학년; 학년 미상 시 5~6학년군 폴백). OCR·진위 프롬프트는 학년군 무관.

## 파일
- `gemini_client.rb` — Gemini `generateContent` Faraday 래퍼. `available?`(키 존재)·`generate(contents:, system_instruction:, ...)`, systemInstruction 을 Content 객체로 감싸고 JSON 응답을 파싱. 실패 시 `NotConfigured`/`ApiError` 를 던지는 것이 계약.
- `review_service.rb` — 5축 발전적 첨삭(RUBRIC). LLM 응답을 `{ level, rubric(5축), praise, fix, grow, pts }` 로 정규화, 무키/실패/스키마이탈 시 `RuleBasedReview` 폴백.
- `rule_based_review.rb` — 외부 호출 없는 규칙기반 5축 첨삭(무중단 폴백). 본문 길이·문장수·감정/삶 어휘 카운트로 축 점수 산출, LLM 경로와 동형 해시 반환.
- `sequel_feedback_service.rb` — 뒷이야기 이어쓰기 격려 코멘트(review_service 미러, 가벼움). 입력=학생이 쓴 뒷이야기 body(+맥락용 book.title/author). **정직한 AI**: 평가 대상이 "책"이 아니라 프롬프트에 든 "학생 글"이라 환각 없음. Gemini 프롬프트는 **초등 전학년(1학년 포함) 격려형**(칭찬 1~2 + 부드러운 제안 1, **점수·등급 금지**, JSON `{comment}`). 무키/실패/스키마이탈 시 `RuleBasedSequelFeedback` 폴백. 반환=코멘트 문자열.
- `rule_based_sequel_feedback.rb` — 외부 호출 없는 규칙기반 뒷이야기 격려 코멘트(무중단 폴백). 글 길이 기반 결정적 템플릿으로 **항상 긍정적** 코멘트 문자열을 반환한다(점수·등급 없음, 크래시 없음).
- `ocr_service.rb` — 손글씨 사진 → 텍스트(Gemini Vision). 이미지 blob 을 Base64 인라인 전송, 키 없으면 `Unavailable` 을 던져 사진 입력 모드 비활성화(Tesseract 등 폴백 없음).
- `quiz_draft_service.rb` — 도서 기반 독서 게임 콘텐츠 생성(QUIZGEN/Phase 2a). 진입점 2개: **`call(book, count:, band:)`**(하위호환 mcq 초안, 교사 퀴즈 CRUD) + **`content_set(book, band, content_axis)`**(Phase 2a 콘텐츠축 세트, AI→오프라인 폴백; Phase 2b Job 진입점). AI 경로는 `ReadingDomain.content_prompt(band, axis)`로 생성 후 **`normalize`가 content_axis별 분기**(count 강제=CONTENT_COUNTS·dedup·정답 검증[mcq 정답 1개·hint_reveal 힌트 최소 2개+타깃]·해설/난이도 파싱). 무키/실패/스키마이탈 시 **`offline_set`가 book.summary/title 파생 결정적 세트**로 폴백(C2, 네트워크 0): mcq=책 제목·지은이·줄거리 토큰 파생(하드코딩 김유신/장영실/구름빵 오답 제거; `place_answer`/`pad_options` 가 오답이 3개 미만이어도[예: 줄거리가 `SUMMARY_DISTRACTOR_POOL` 낱말을 대부분 포함해 오답 후보가 부족한 경우] `GENERIC_FILLER_DISTRACTORS` 로 패딩해 **보기 항상 정확히 4개·서로 중복 없음**을 보장 — 오프라인 경로는 Moderator 게시 전 검증을 거치지 않고 학생에게 바로 노출되므로 이 계약을 서비스 스스로 지켜야 함), hint_reveal=책 제목/지은이/줄거리 토큰 타깃 + 어려움→쉬움 안전 힌트. summary 없으면 일반 독해로 우아하게 강등, 모든 축 band별 상이. 반환 해시는 두 경로 동형(`{ question_type, prompt, content, answer, explanation, difficulty }`; mcq 는 하위호환용 `choices`/`answer_index` 병기). 오프라인 품질 < AI(정직화). **게임 재구성 Phase 1**: matching(vocab) 생성 경로(`offline_matching`·`normalize_matching`·`READING_TERMS_BY_BAND`) 제거 — mcq·hint_reveal 만 생성한다(Quiz#content_axis matching·QuestionScorer matching 은 휴면 보존).
- `verify_service.rb` — 진위·표절 의심 보조(VERIFY) + `self.max_similarity`(학급 내 독후감 Jaccard 최대 유사도, 순수 Ruby). 무키/실패 시 중립값(`suspicion: nil`).
- `quiz_moderator.rb` — **온디맨드 게임 콘텐츠 게시 전 안전 검증기(Phase 2b §2b.3, R4/시나리오2)**. `review(set, content_axis:)`가 `GenerateGameContentJob`이 AI 세트를 학생에게 게시하기 **전에** pass/fail 을 판정한다(통과분만 게시, 실패분은 오프라인 유지·원문 미노출). **보장하는 것은 정확히**: ① 구조 유효성(content_axis별 count=CONTENT_COUNTS, mcq_single 정답 정확히 1개·범위 내 / matching 정답키 개수·범위·쌍 수 / hint_reveal 힌트≥2+타깃, 보기·우측 상호 배타[중복 없음], 인덱스 범위) ② 결정적 한국어 금칙어 denylist(**`Moderation::TextDenylist::QUIZ` 위임** — `DENYLIST` 상수는 그 별칭. 토론 자유입력은 오탐 낱말을 뺀 `FORUM` 리스트를 쓰지만 quiz 는 기존 동작 보존차 QUIZ 리스트 유지) ③ (선택)LLM 자가검토(키 있을 때만; 무키·실패는 거부 사유 아님). **보장하지 않는 것(정직화)**: 미묘한 환각 정답·편향·맥락 부적절 — 이는 강제 게이트가 아니라 신고(reported)+content_version 재생성+스코프 kill switch+지표로 사후 회수(ADR 잔여위험). 반환은 `Result#pass?/#fail?/#reasons`. matching 은 문항 1개에 count개 쌍을 담는 구조라 count 검증을 축별로 보정.

## 패턴·규칙
- **키 유무 폴백 흐름**: 각 서비스는 진입 시 `@client.configured?` 를 확인한다. 키가 없으면 즉시 폴백 경로(`review`→규칙기반, `quiz_draft`→오프라인 템플릿, `verify`→중립값, `ocr`→`Unavailable` 예외)로 분기하고, 키가 있어도 `GeminiClient::NotConfigured`/`ApiError`(및 각 서비스의 `InvalidResponse`)를 rescue 해 같은 폴백으로 흡수한다. 결과적으로 AI 기능은 무중단이며 응답 형태가 LLM/폴백 간 동일하다.
- **테스트 주입**: 모든 서비스는 `initialize(client:)`(또는 `GeminiClient.new(connection:)`)로 스텁을 주입해 네트워크 없이 검증한다.
- **개인정보 보호**: 예외 로깅 시 `report.body` 등 학생 원문은 로그에 남기지 않고 예외 클래스·상태코드만 기록한다(`verify_service.rb`).

---
> ⚠️ **유지보수 규칙**: 이 폴더의 파일이 추가·삭제되거나 역할이 바뀌면 이 CLAUDE.md도 함께 갱신하세요. 하위 폴더 구조가 바뀌면 관련 상·하위 CLAUDE.md 링크도 확인하세요.
