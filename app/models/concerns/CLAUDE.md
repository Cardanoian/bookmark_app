# app/models/concerns — 모델 mixin 모듈 (게임 루프·루브릭·도메인 상수)

`app/models`의 모델에 `include`되는 재사용 concern 모듈들입니다. 포인트 적립→뱃지→진화로 이어지는 게이미피케이션 루프의 4개 축(Pointable·Leveling·Evolvable·Badgeable)은 모두 `User`에 얹혀 협력하고, RubricScorable는 `Report`의 5축 채점을 맡습니다. ReadingDomain은 모델이 아닌 서비스·잡·다른 concern이 공유하는 순수 상수 모듈입니다.

## 파일
> **현재 랭킹 방송 정책**: `Pointable#broadcast_ranking_change`는 모든 학급 학생을 갱신한다. 비공개 학생은 집계에서는 빠지지 않으며, 랭킹 파셜이 닉네임·몬스터를 비식별 처리한다.

- `pointable.rb` — **User** mixin. `award_points`는 포인트·경험치를 원자 증가한 뒤 뱃지·진화·랭킹 방송을 연쇄하고, `spend_points!`는 조건부 차감으로 double-spend를 막는다. 미션 보상은 `credit_points!`로 트랜잭션 안에 적립하고 커밋 뒤 `run_point_side_effects!`로 후크를 실행한다. 시즌 점수는 `increment_season_score!` raw upsert와 `decrement_season_score!` 하향으로 현재 학년도에 분리 축적하며, 포인트 소비는 시즌 경험치를 줄이지 않는다. `broadcast_ranking_change`는 공개 설정과 무관하게 모든 학급 학생의 Turbo 행을 갱신하고, 비공개 식별 처리는 랭킹 파셜에 맡긴다.
- `leveling.rb` — **User** mixin. 누적 포인트 임계(LEVEL_PATH)로 트레이너 레벨(1..6)·칭호(TRAINER_TITLES) 계산.
- `evolvable.rb` — **User** mixin. 활성/보유 몬스터의 진화 가능 여부 판정(`check_evolution!`·`evolvable_monsters`)과 필요 포인트 차감+진화를 원자 처리하는 `evolve_monster!`/`evolve_active_monster!`.
- `badgeable.rb` — **User** mixin. `refresh_badges!`가 Badge::KEYS 13종 조건을 `ReadingStats`로 평가해 충족 뱃지를 멱등 부여. 도감 뱃지 분모는 설계 라인 24 고정.
- `rubric_scorable.rb` — **Report** mixin. 5축 루브릭 해시→가중평균·A/B/C 등급·포인트 산정. 핵심 로직(`score_rubric`/`level_for`)은 AR 인스턴스 없이도 쓰도록 모듈 함수로도 노출.
- `reading_domain.rb` — mixin 아님(상수 모듈). 5축 키·한국어 라벨·2022 개정 성취기준 코드·등급 포인트·기본 가중치와 OCR/루브릭/퀴즈생성/진위 판별 AI 프롬프트를 한곳에서 관리. **성취기준·루브릭 프롬프트·추천활동·퀴즈 프롬프트는 학년군(g12/g34/g56)별로 분기**하며, `band_for(grade)`·`achievement_standards(band)`·`rubric_prompt(band)`·`quizgen_prompt(band)` 접근자로 얻는다. **학년 눈높이 봉쇄(성취기준 allowlist)**: `ACHIEVEMENT_STANDARDS_BY_BAND`(5축 대표 코드 1개씩)와 별개로 `CURRICULUM_STANDARDS_BY_BAND`(학년군별 국어 성취기준 **전체 목록** — 읽기·쓰기·문법·문학 4영역, 출처 `app/views/monsters/성취기준.md`)를 두고, `build_rubric_prompt`가 이 목록(`standards_allowlist(band)`)을 프롬프트에 통째로 주입 + "이 목록 밖 코드·상위 학년 수준 요구 금지" 하드 제약을 건다(3학년에게 6학년 성취기준을 근거로 첨삭하는 문제 차단). 대표 5축 코드는 반드시 이 전체 목록의 부분집합이어야 한다(테스트 가드). **게임 플레이 전용 `game_band_for(grade)`**(후속 정밀화)는 학년 미상(nil/0)을 band_for 의 g56 이 아니라 **최저 밴드 g12** 로 고정해 학급 없는 학생에게 5~6학년 콘텐츠를 기본 매칭하지 않는다(첨삭·대시보드의 band_for 는 불변). 학년군 인자 없이 쓰는 flat 상수(`ACHIEVEMENT_STANDARDS`·`RUBRIC_PROMPT` 등)는 5~6학년군(g56) 기본값으로 하위호환. **`CONTENT_COUNTS`**(Phase 1)는 content_axis(mcq/hint_reveal)별 고정 문항 수로, 콘텐츠축 상한 비교(point_award)의 스케일 일관성과 생성(Phase 2a normalize) 강제의 단일 진실(게임 재구성 Phase 1: matching 생성 경로 제거로 matching 키 삭제). **`build_content_prompt(band, content_axis)`**(Phase 2a)는 `build_quizgen_prompt`(mcq 4지선다)의 일반화 — band 성취기준·눈높이 + 난이도 티어 + 오답 품질 + 해설 강제 + 중복 방지 + count 강제(CONTENT_COUNTS) + 근거 한정(환각 억제) + content_axis별 JSON 스키마(mcq=choices/answer_index / hint_reveal=targets+hints)를 주입한다. **`CONTENT_PROMPTS`**는 `(band × content_axis)`를 로드 시점에 사전빌드·동결하고, `content_prompt(band, content_axis)` 접근자(미지원 band/axis → g56/mcq 폴백)로 얻는다. `QuizDraftService`(AI 경로 system_instruction)·RubricScorable·백그라운드 잡·게임 서비스가 참조. **독후감 안내 질문(직접쓰기 학습단계·사진쓰기 가이드 모달)**: `GUIDED_QUESTIONS_BY_BAND`(밴드별 서론→본론(다수)→결론 흐름 질문 세트 — 문항 수 g12 5·g34 7·g56 8, 각 문항 `{axis(5축 내부 태그)·part(intro/body/conclusion)·question·hint·example}` + `ratio_hint`[줄거리 20~30%/생각·느낌 70~80% 비중 안내]·`spelling_tip`) + `guided_questions(band)`(미지원 band → g56 폴백, 항상 non-empty Hash) + **`guided_band_for(grade)`**(아동 대면 온디맨드 전용 폴백 — 학년 미상[nil/0]을 첨삭용 `band_for`의 g56 이 아니라 **최저 밴드 g12** 로, `game_band_for` 동형 age-safety). `ReportsController#new`가 `@guided`로 세팅해 `reports/_guided_compose`·`_photo_guide`가 소비.

## 패턴·규칙
- **User가 4개 concern의 교차점**: Pointable이 적립 시 Badgeable·Evolvable을 연쇄 호출하므로, 세 모듈은 반드시 함께 include된 상태를 전제한다.
- **상수 vs mixin 구분**: `reading_domain.rb`는 `include`하지 않고 `ReadingDomain::RUBRIC_AXES`처럼 상수로 참조한다. 나머지 5개는 모델에 `include`한다.
- **트랜잭션 경계 주의**: `spend_points!`는 의도적으로 reload·방송을 하지 않는다(롤백 오염 방지). 커밋 후 reload·랭킹 방송은 호출자 책임(§0.3).

---
> ⚠️ **유지보수 규칙**: 이 폴더의 파일이 추가·삭제되거나 역할이 바뀌면 이 CLAUDE.md도 함께 갱신하세요. 하위 폴더 구조가 바뀌면 관련 상·하위 CLAUDE.md 링크도 확인하세요.
