# 「책갈피」 반려 몬스터 도감 시드 설계서

> **목적**: `RAILS_PLAN.md` §13.5(반려 몬스터 도감·진화)의 **실제 콘텐츠 시드**. 아바타를 대체하는 수집형 반려 몬스터의 종·진화 라인·진화 조건·AI 이미지 생성 가이드를 착수 가능한 수준으로 정의한다.
>
> 대상: 초등학교 전학년. 포켓몬스터·디지몬처럼 아이들이 좋아할 크리처를 담되, **주변에서 흔히 보는 친숙한 동물·사물**(강아지·고양이·햄스터·펭귄, 연필·로봇 등)을 몬스터화한다. 판타지 종(용·유니콘·도깨비·나비)은 상상 속성에만 배치하고, 모든 종은 **완전 오리지널**(기존 IP 모방 금지 — 법적·대회 리스크)로 디자인한다.
> 최종 수정: 2026-07-08 (종 이름·생김새 묘사를 아트 파이프라인 `script/monster.json` 기준으로 통일)

---

## 1. 개요

- **규모**: 진화 라인 **24개**(6속성 × 4계열), 각 라인 **3단계**(기본형 → 성장형 → 완전형) = **72폼**.
- **컨셉**: 일상에서 볼 수 있는 **친숙한 동물·사물**을 몬스터화(동물 위주 + 사물 소수). 아이들이 "내 반려동물" 같은 애착을 느끼도록 하되, 각 종은 속성별 독서 습관과 연결된다(§2).
- **수집(도감) 방식**: 학생마다 도감을 채워 나감. 첫 **스타터 1종 선택**(서로 다른 속성 후보 중), 이후 독후감·장르·게임·미션 등 **마일스톤마다 신규 몬스터 자동 발견**(가챠 없음). 24종의 구체적인 해금 조건과 집계 계약은 [`monster_unlocks.md`](./monster_unlocks.md)를 따른다.
- **진화**: 포인트 임계 **+ 독서 행동 조건** 조합. 라인마다 성격이 달라 서로 다른 독서 습관을 유도한다(§4, §5).
- **시드·에셋 상태**: **데이터(종·진화라인·조건)와 애니메이션 WebP는 24라인 72폼 전량 반영 완료**(데이터 2026-07-08, 에셋 2026-07-12). `phase:` 필드는 아트 제작 배치를 표시할 뿐, 시더는 전량 적재한다.
- 이 문서의 각 항목은 `monster_species` 스키마(dex_no·stage·key·name·element·rarity·evolves_from·evolve_condition·image_key·description)에 1:1 매핑된다.

---

## 2. 6속성 체계

각 속성은 유도하려는 독서 습관과 시각 톤을 가진다. 친숙한 동물·사물을 쓰되 속성 성격에 맞춰 배정한다.

| 속성(element) | 한글 | 대표색 | 성격 | 진화가 유도하는 독서 습관 | 대표 종(예) |
|------|------|--------|------|-----------|------|
| `story` | 이야기 | 보라 | 이야기·글쓰기 | 꾸준한 독후감 작성·표현·토론 | 강아지·앵무새·연필·여우 |
| `knowledge` | 지식 | 파랑 | 지혜·탐구 | 다양한 장르·고전·퀴즈·탐구 | 고양이·부엉이·로봇·거북이 |
| `emotion` | 감성 | 분홍 | 마음·공감 | 감상 표현·삶과 연결(A등급)·응원 | 햄스터·아기고래·토끼·사슴 |
| `adventure` | 모험 | 주황 | 용기·도전 | 연속 독서 스트릭·미션·챌린지 | 곰·병아리·펭귄·공룡 |
| `nature` | 자연 | 초록 | 성실·성장 | 성실한 활동·고쳐쓰기·성장 | 고슴도치·개구리·다람쥐·버섯 |
| `imagination` | 상상 | 무지개/금 | 창의·종합 | 도감 수집·창의 활동·종합 성취(최고난도) | 유니콘·나비·도깨비·용 |

> **질 우선 정렬**: 완전형(3단계) 조건에 A등급·삶과 연결·고전·고쳐쓰기·도감 수집 등을 배치해, 게임화가 `RAILS_PLAN.md` §1.3 "발전적 첨삭" 가치와 정렬되도록 한다.

---

## 3. 아트 스타일 바이블 (AI 이미지 생성 공통 가이드)

72폼을 서로 다른 AI 이미지로 만들되 **하나의 도감처럼 통일**되어야 한다. 아래 규칙을 모든 이미지에 공통 적용한다.

### 3.1 공통 스펙
- **스타일**: 부드러운 셀 셰이딩(soft cel-shading), **굵고 깔끔한 외곽선**, 파스텔+비비드 혼합, 아동친화 마스코트 톤.
- **비례**: 마스코트형 통일 실루엣. 사람형(여우 이야기꾼·거북 선인 등)은 앱 캐릭터와 동일한 **5등신** 비례, 동물·사물형은 둥글고 큰 머리의 치비 실루엣.
- **친숙함 규칙**: 강아지·고양이처럼 흔한 동물은 반드시 **오리지널 한 끗**(고유 색·상징 요소·실루엣)을 넣어 기존 IP나 실물 사진과 구분되게 한다.
- **포즈/구도**: 정면 3/4, 전신, 중앙 정렬, 밝은 상단 조명, 큰 눈·또렷한 표정.
- **캔버스**: 정사각형 1024×1024 원본을 앱용 **애니메이션 WebP**로 출력(그림자 없음 또는 아주 옅은 접지 그림자 옵션).
- **금지**: 텍스트·워터마크·서명·로고, 배경 장식, 기존 캐릭터(포켓몬/디지몬/기타 IP) 유사, 무섭거나 사실적인 묘사.
- **파일**: `image_key` = 슬러그(예: `pup_1`) → `app/assets/images/monsters/pup_1.webp`.

### 3.2 마스터 프롬프트 템플릿
```
A cute original creature mascot for a children's reading app, "{이미지 주제}",
{속성 팔레트} color palette, soft cel-shading, thick clean outlines,
big expressive eyes, chibi/mascot proportions, front three-quarter full-body view,
centered, soft top lighting, flat transparent background, sticker-style,
wholesome and friendly, original design (NOT resembling any existing franchise).
```
- `{이미지 주제}` = 각 폼의 "이미지 주제" 한 줄(§5)을 영어로 옮겨 넣는다.
- `{속성 팔레트}` = §3.4의 속성별 색.

### 3.3 네거티브 프롬프트(권장)
```
text, letters, watermark, signature, logo, background scenery, realistic, scary,
gore, extra limbs, Pokemon, Digimon, copyrighted character, brand mascot
```

### 3.4 속성별 팔레트·무드
| 속성 | 팔레트 키워드 | 무드 |
|------|--------------|------|
| story | violet, lavender, cream | 포근·이야기책 |
| knowledge | blue, teal, silver | 또렷·똑똑 |
| emotion | pink, rose, peach | 다정·말랑 |
| adventure | orange, amber, red | 활기·용감 |
| nature | green, mint, brown | 싱그러움·성실 |
| imagination | rainbow, gold, iris | 반짝·환상 |

### 3.5 진화 단계 시각 규칙(연속성)
같은 라인의 3폼은 **색 모티프·상징을 유지**하며 성장해야 도감에서 한 가족으로 읽힌다.
- **1단계(기본형)**: 작고 동글, 아기 느낌, 상징 요소가 작게 1개.
- **2단계(성장형)**: 키·디테일 증가, 상징 요소 강화, 액세서리 1~2개 추가.
- **3단계(완전형)**: 크고 당당, 날개/왕관/망토 등 "완성" 실루엣, 은은한 발광 이펙트 가능.

### 3.6 완성 예시 프롬프트(3종)
- **pup_1 (갈피멍)**:
  `A cute original creature mascot for a children's reading app, "a tiny fluffy cream puppy with a lavender bookmark-ribbon tail, floppy ears, big round eyes", violet lavender cream color palette, soft cel-shading, thick clean outlines, big expressive eyes, chibi proportions, front three-quarter full-body view, centered, soft top lighting, flat transparent background, sticker-style, original design.`
- **owl_2 (반짝부엉)**:
  `... "a small round owl with a glowing idea-lightbulb floating above its head, fluffy feathers", blue teal silver color palette, ... chibi proportions ...`
- **dragon_3 (상상용)**:
  `... "a majestic small dragon with rainbow-iridescent scales, star-cloud wings, gentle glowing aura, regal but friendly", rainbow gold iris color palette, ... confident full-body pose ...`

---

## 4. 진화 조건 키 사전

`evolve_condition`(JSON)에 쓰는 키. 각 값은 "누적 도달 목표". 여러 키가 있으면 **AND**(모두 충족).

| 키 | 의미 | 집계 소스 |
|----|------|-----------|
| `points` | 누적 트레이너 포인트 | `user.points` |
| `reports` | 승인된 독후감 수 | `reports.where(reviewed: true)` |
| `distinct_genres` | 서로 다른 도서 카테고리 수 | `books.category` distinct |
| `a_grades` | A등급 첨삭 수 | `reports.where(level: "A")` |
| `b_or_better` | B등급 이상 수 | `reports.where(level: %w[A B])` |
| `classics` | 완독한 고전 수 | `category: classic` 연동 독후감 |
| `revisions` | 향상된 고쳐쓰기 수 | `reports.where("improvement > 0")` |
| `streak_days` | 연속 독서일 | 연속 독서/제출 스트릭 |
| `missions` | 참여 미션 수 | `mission_id` 있는 report distinct |
| `challenges` | 완료 챌린지 수 | 챌린지 달성 기록 |
| `quizzes` | 퀴즈/게임 플레이 수 | `quiz_attempts` + 게임 로그 |
| `topic_posts` | 토론 글 수 | `forum_posts.by(user)` |
| `cheers_received` | 받은 응원 수 | `reports` → `board_posts.cheers` 합 |
| `dex_count` | 보유 몬스터(라인) 수 | `user_monsters` distinct dex_no |
| `badge` | 특정 뱃지 보유 | `user_badges`의 badge key |

> 평가 시점: `Evolvable` concern이 **독후감 승인·포인트 지급·뱃지 획득·게임 종료** 훅에서 활성 몬스터의 조건을 검사 → 충족 시 "진화 가능!" 배지 표시(학생이 실행하거나 자동).

---

## 5. 도감 (24라인 × 3단계)

각 속성 섹션은 **폼 표**(이미지 제작용)와 **진화 조건 표**로 구성. `key`는 슬러그 겸 `image_key`.

### 5.1 이야기 (STORY) — dex 1~4 · 보라

| dex | 계열 | 등급 | 단계 | key | 이름 | 이미지 주제 |
|----|------|------|------|-----|------|-------------|
| 1 | 강아지 ★스타터 | common | 1 | `pup_1` | 갈피멍 | 라벤더 책갈피 리본 꼬리를 단 폭신한 아기 강아지 |
| 1 | 강아지 | common | 2 | `pup_2` | 이야기멍 | 작은 이야기책을 입에 물고 리본 스카프를 두른 강아지 |
| 1 | 강아지 | common | 3 | `pup_3` | 전설멍 | 책장 망토와 빛나는 책갈피 리본에 작은 왕관·금빛 장식을 두른 늠름한 수호견 |
| 2 | 앵무새 | rare | 1 | `parrot_1` | 쫑알이 | 햇살 노랑 솜털에 청록빛 날개 끝, 책장 무늬 깃털 하나를 단 동글동글 아기 앵무새 |
| 2 | 앵무새 | rare | 2 | `parrot_2` | 수다앵무 | 노랑·청록 깃털과 작은 볏을 뽐내며 펼친 책 위에서 이야기하는 앵무새 |
| 2 | 앵무새 | rare | 3 | `parrot_3` | 이야기봉황 | 노랑·청록 깃털에 금빛이 어린, 펼친 책장처럼 빛나는 날개의 이야기 봉황 앵무새 |
| 3 | 연필 | common | 1 | `pencil_1` | 뾰족이 | 라벤더빛 목재 몸통에 둥근 심과 큰 눈의 작은 연필 정령 |
| 3 | 연필 | common | 2 | `pencil_2` | 또각연필 | 작은 팔로 공책을 든 키 큰 연필 친구 |
| 3 | 연필 | common | 3 | `pencil_3` | 글씨봉 | 금빛 심과 흘러나오는 글자 리본을 두른 연필 마법사 |
| 4 | 여우 | rare | 1 | `fox_1` | 도담여우 | 옛이야기 두루마리를 안은 작은 아기 여우 |
| 4 | 여우 | rare | 2 | `fox_2` | 이야기여우 | 갓을 쓰고 한복 조끼를 입은 채 두 발로 서서 두루마리를 든 영리한 여우 |
| 4 | 여우 | rare | 3 | `fox_3` | 만담여우 | 도포를 걸치고 빛나는 옛책을 든 다정한 여우 이야기꾼 |

| dex | 계열 | 1→2 조건 | 2→3 조건 |
|----|------|----------|----------|
| 1 | 강아지 | `points:100, reports:3` | `points:450, a_grades:1, b_or_better:5` |
| 2 | 앵무새 | `points:100, reports:5` | `points:700, reports:12, a_grades:2` |
| 3 | 연필 | `points:150, topic_posts:2` | `points:450, a_grades:2` |
| 4 | 여우 | `points:150, distinct_genres:2` | `points:700, classics:1, reports:8` |

### 5.2 지식 (KNOWLEDGE) — dex 5~8 · 파랑

| dex | 계열 | 등급 | 단계 | key | 이름 | 이미지 주제 |
|----|------|------|------|-----|------|-------------|
| 5 | 고양이 ★스타터 | common | 1 | `cat_1` | 아롱냥 | 은회색 털에 큰 파란 목도리를 두른 호기심 많은 아기 고양이 |
| 5 | 고양이 | common | 2 | `cat_2` | 안경냥 | 은회색 털에 동그란 파란 안경과 목도리를 한 똑똑한 고양이 |
| 5 | 고양이 | common | 3 | `cat_3` | 지혜냥 | 별자리 지도 망토와 은빛 왕관을 두른 현자 고양이 |
| 6 | 부엉이 | common | 1 | `owl_1` | 동글부엉 | 큰 눈의 동글동글 아기 부엉이 |
| 6 | 부엉이 | common | 2 | `owl_2` | 반짝부엉 | 머리 위에 반짝이는 아이디어 전구를 띄운 부엉이 |
| 6 | 부엉이 | common | 3 | `owl_3` | 아이디어부엉 | 별똥별 깃털과 빛나는 전구 왕관의 지혜 부엉이 |
| 7 | 로봇 | rare | 1 | `robot_1` | 도르리 | 작은 톱니바퀴 몸통의 아기 로봇 |
| 7 | 로봇 | rare | 2 | `robot_2` | 째깍로봇 | 태엽과 계기판 몸통의 발명 로봇 |
| 7 | 로봇 | rare | 3 | `robot_3` | 발명로봇 | 기계 날개와 빛나는 안테나의 거대 발명 로봇 |
| 8 | 거북이 | epic | 1 | `turtle_1` | 조각등 | 작은 수정 무늬 등껍질의 아기 거북 |
| 8 | 거북이 | epic | 2 | `turtle_2` | 지식거북 | 책 문양이 새겨진 등껍질과 이끼 수염의 거북 |
| 8 | 거북이 | epic | 3 | `turtle_3` | 만물거북 | 지식 룬이 빛나는 거대한 등껍질의 현자 거북 |

| dex | 계열 | 1→2 조건 | 2→3 조건 |
|----|------|----------|----------|
| 5 | 고양이 | `points:100, distinct_genres:2` | `points:450, distinct_genres:4` |
| 6 | 부엉이 | `points:100, quizzes:3` | `points:450, quizzes:8, a_grades:1` |
| 7 | 로봇 | `points:150, missions:1` | `points:700, distinct_genres:5, quizzes:5` |
| 8 | 거북이 | `points:250, classics:1` | `points:1000, classics:3, distinct_genres:5` |

### 5.3 감성 (EMOTION) — dex 9~12 · 분홍

| dex | 계열 | 등급 | 단계 | key | 이름 | 이미지 주제 |
|----|------|------|------|-----|------|-------------|
| 9 | 햄스터 ★스타터 | common | 1 | `hamster_1` | 콩닥이 | 볼이 발그레하고 양 볼에 하트를 담은 작은 아기 햄스터 |
| 9 | 햄스터 | common | 2 | `hamster_2` | 두근이 | 작은 하트를 볼에 담아 두근대는 햄스터 |
| 9 | 햄스터 | common | 3 | `hamster_3` | 사랑햄둥이 | 큰 하트 귀와 폭신한 꼬리의 천사 햄스터 |
| 10 | 고래 | common | 1 | `whale_1` | 또르고래 | 물방울 하나를 이고 있는 작은 아기 고래 |
| 10 | 고래 | common | 2 | `whale_2` | 촉촉고래 | 눈물 구슬 목걸이를 두른 감성 아기 고래 |
| 10 | 고래 | common | 3 | `whale_3` | 무지개고래 | 무지갯빛 물을 뿜는 큰 감동 고래 |
| 11 | 토끼 | rare | 1 | `rabbit_1` | 몽실토끼 | 기분 따라 귀 모양이 바뀌는 작은 토끼 |
| 11 | 토끼 | rare | 2 | `rabbit_2` | 뭉게토끼 | 무지개 리본 귀를 단 토끼 |
| 11 | 토끼 | rare | 3 | `rabbit_3` | 노을토끼 | 노을빛 긴 귀와 별 무늬의 다정한 큰 토끼 |
| 12 | 사슴 | common | 1 | `deer_1` | 새싹사슴 | 잎 새싹 뿔이 돋은 아기 사슴 |
| 12 | 사슴 | common | 2 | `deer_2` | 꽃봉사슴 | 반쯤 핀 꽃 뿔의 사슴 |
| 12 | 사슴 | common | 3 | `deer_3` | 만개사슴 | 활짝 핀 꽃뿔의 우아한 큰 사슴 |

| dex | 계열 | 1→2 조건 | 2→3 조건 |
|----|------|----------|----------|
| 9 | 햄스터 | `points:100, reports:3` | `points:450, a_grades:2` |
| 10 | 고래 | `points:100, b_or_better:3` | `points:450, a_grades:3` |
| 11 | 토끼 | `points:150, cheers_received:5` | `points:700, a_grades:3, cheers_received:15` |
| 12 | 사슴 | `points:100, reports:4` | `points:450, a_grades:2, revisions:1` |

### 5.4 모험 (ADVENTURE) — dex 13~16 · 주황

| dex | 계열 | 등급 | 단계 | key | 이름 | 이미지 주제 |
|----|------|------|------|-----|------|-------------|
| 13 | 곰 ★스타터 | common | 1 | `bear_1` | 방향곰 | 작은 나침반 목걸이를 건 아기 곰 |
| 13 | 곰 | common | 2 | `bear_2` | 탐험곰 | 탐험가 모자와 배낭을 멘 곰 |
| 13 | 곰 | common | 3 | `bear_3` | 곰선장 | 망토와 깃발을 든 대탐험가 곰 |
| 14 | 병아리 | common | 1 | `chick_1` | 반디병아리 | 반딧불 같은 작은 불씨 볏의 아기 병아리 |
| 14 | 병아리 | common | 2 | `chick_2` | 활활닭 | 불꽃 볏과 꽁지의 용감한 닭 |
| 14 | 병아리 | common | 3 | `chick_3` | 불꽃장닭 | 불꽃빛 볏과 화려한 꽁지깃을 세운 용맹한 큰 장닭 |
| 15 | 펭귄 | rare | 1 | `penguin_1` | 붕붕펭 | 작은 별 헬멧을 쓴 아기 펭귄 |
| 15 | 펭귄 | rare | 2 | `penguin_2` | 슝슝펭 | 로켓 배낭을 멘 펭귄 우주비행사 |
| 15 | 펭귄 | rare | 3 | `penguin_3` | 은하펭선장 | 은하 망토를 두른 우주 탐험 펭귄 |
| 16 | 공룡 | rare | 1 | `dino_1` | 알록공 | 알록달록 알에서 반쯤 나온 아기 공룡 |
| 16 | 공룡 | rare | 2 | `dino_2` | 티라돌 | 탐험 손수건을 두른 작은 티라노 |
| 16 | 공룡 | rare | 3 | `dino_3` | 모험왕티라노 | 갑옷을 두른 용맹한 티라노 |

| dex | 계열 | 1→2 조건 | 2→3 조건 |
|----|------|----------|----------|
| 13 | 곰 | `points:100, missions:1` | `points:450, streak_days:5, missions:2` |
| 14 | 병아리 | `points:100, streak_days:3` | `points:700, streak_days:7` |
| 15 | 펭귄 | `points:150, quizzes:3` | `points:700, streak_days:10, challenges:1` |
| 16 | 공룡 | `points:150, reports:5` | `points:700, missions:3, streak_days:7` |

### 5.5 자연 (NATURE) — dex 17~20 · 초록

| dex | 계열 | 등급 | 단계 | key | 이름 | 이미지 주제 |
|----|------|------|------|-----|------|-------------|
| 17 | 고슴도치 ★스타터 | common | 1 | `hedgehog_1` | 새싹도치 | 등에 새싹이 돋은 작은 아기 고슴도치 |
| 17 | 고슴도치 | common | 2 | `hedgehog_2` | 잎사귀도치 | 잎사귀 가시 망토를 두른 고슴도치 |
| 17 | 고슴도치 | common | 3 | `hedgehog_3` | 숲지기도치 | 작은 나무가 자란 등의 숲지기 고슴도치 |
| 18 | 개구리 | common | 1 | `frog_1` | 퐁당올챙 | 물방울 같은 작은 올챙이 |
| 18 | 개구리 | common | 2 | `frog_2` | 시냇개구리 | 시냇물에서 노는 아기 개구리 |
| 18 | 개구리 | common | 3 | `frog_3` | 개굴대왕 | 연잎 왕관을 쓰고 강을 다스리는 큰 개구리신 |
| 19 | 다람쥐 | common | 1 | `squirrel_1` | 도토리 | 도토리를 안은 아기 다람쥐 |
| 19 | 다람쥐 | common | 2 | `squirrel_2` | 볼록이 | 볼이 빵빵한 다람쥐 |
| 19 | 다람쥐 | common | 3 | `squirrel_3` | 숲요정다래 | 나뭇잎 왕관의 다람쥐 요정 |
| 20 | 버섯 | rare | 1 | `mushroom_1` | 몽글버섯 | 작은 버섯 정령 |
| 20 | 버섯 | rare | 2 | `mushroom_2` | 우산버섯 | 우산을 쓴 버섯 |
| 20 | 버섯 | rare | 3 | `mushroom_3` | 신비버섯 | 빛나는 포자의 신비 버섯 정령 |

| dex | 계열 | 1→2 조건 | 2→3 조건 |
|----|------|----------|----------|
| 17 | 고슴도치 | `points:100, reports:3` | `points:450, revisions:1, reports:8` |
| 18 | 개구리 | `points:100, reports:4` | `points:450, revisions:2` |
| 19 | 다람쥐 | `points:100, missions:1` | `points:450, distinct_genres:3, reports:8` |
| 20 | 버섯 | `points:150, streak_days:3` | `points:700, revisions:2, streak_days:7` |

### 5.6 상상 (IMAGINATION) — dex 21~24 · 무지개/금

| dex | 계열 | 등급 | 단계 | key | 이름 | 이미지 주제 |
|----|------|------|------|-----|------|-------------|
| 21 | 유니콘 ★스타터 | rare | 1 | `unicorn_1` | 꼬마유니콘 | 이마에 작은 별이 반짝이는 아기 유니콘 |
| 21 | 유니콘 | rare | 2 | `unicorn_2` | 꿈별유니콘 | 별 갈기의 아기 유니콘 |
| 21 | 유니콘 | rare | 3 | `unicorn_3` | 별자리유니콘 | 별자리 갈기와 무지개 뿔의 유니콘 |
| 22 | 나비 | rare | 1 | `butterfly_1` | 물감애벌레 | 알록달록 물감 무늬의 작은 애벌레 |
| 22 | 나비 | rare | 2 | `butterfly_2` | 무지개고치 | 무지갯빛으로 빛나는 나비 번데기 |
| 22 | 나비 | rare | 3 | `butterfly_3` | 무지개나비 | 무지개 물감 날개의 아름다운 큰 나비 |
| 23 | 도깨비 | common | 1 | `dokkaebi_1` | 방울깨비 | 적갈색 피부에 작은 뿔, 방울 달린 나무 방망이를 든 아기 도깨비 |
| 23 | 도깨비 | common | 2 | `dokkaebi_2` | 뿔깨비 | 적갈색 피부에 커진 뿔, 호랑이 줄무늬 허리천과 못 박힌 방망이의 장난꾸러기 도깨비 |
| 23 | 도깨비 | common | 3 | `dokkaebi_3` | 무쌍깨비 | 적갈색 피부에 큰 뿔, 호랑이 줄무늬 망토와 금빛 방망이를 든 도깨비 대장 |
| 24 | 용 | epic | 1 | `dragon_1` | 알드래 | 무지개 용알에서 반쯤 나온 아기 용 |
| 24 | 용 | epic | 2 | `dragon_2` | 뭉치용 | 구름 같은 몸의 새끼 용 |
| 24 | 용 | epic | 3 | `dragon_3` | 상상용 | 무지갯빛 거대한 상상의 용 |

| dex | 계열 | 1→2 조건 | 2→3 조건 |
|----|------|----------|----------|
| 21 | 유니콘 | `points:150, quizzes:3` | `points:700, dex_count:5, a_grades:2` |
| 22 | 나비 | `points:150, distinct_genres:3` | `points:700, dex_count:6, revisions:1` |
| 23 | 도깨비 | `points:100, quizzes:3` | `points:450, dex_count:4, missions:2` |
| 24 | 용 | `points:250, dex_count:5` | `points:1000, dex_count:10, a_grades:3, classics:2` |

---

## 6. 스타터 & Phase 1 시드

### 6.1 스타터(첫 선택 3종)
서로 다른 속성·분위기로 균형: 학생이 가입 직후 1종 선택. 가장 친숙하고 사랑받는 반려동물로 구성.
- `pup_1` **갈피멍**(story, 브랜드 상징 강아지 — 책갈피 리본 계승)
- `cat_1` **아롱냥**(knowledge, 호기심 많은 고양이)
- `hedgehog_1` **새싹도치**(nature, 옛 성장단계 오마주)

> 선택하지 않은 스타터도 나중에 활동 조건으로 얻을 수 있다. 스타터를 포함한 24개 라인의 정확한 자동 해금 조건은 [`monster_unlocks.md`](./monster_unlocks.md)에 정의한다.

### 6.2 아트 제작 단계(Phase) — 데이터는 전량 시드
데이터(종·진화조건)는 24라인 전량 시드됐다. 아래 Phase 구분은 **AI 이미지(PNG) 제작 배치**를 뜻하며(`monster_lines[].phase`), 시더(`MonsterSeeder.seed_all!`)는 phase 무관 전량 적재한다.

| 속성 | Phase 1 라인(에셋 우선) | Phase 2 라인 |
|------|--------------|--------------|
| story | 강아지(1) · 앵무새(2) | 연필(3) · 여우(4) |
| knowledge | 고양이(5) · 부엉이(6) | 로봇(7) · 거북이(8) |
| emotion | 햄스터(9) · 고래(10) | 토끼(11) · 사슴(12) |
| adventure | 곰(13) · 병아리(14) | 펭귄(15) · 공룡(16) |
| nature | 고슴도치(17) · 개구리(18) | 다람쥐(19) · 버섯(20) |
| imagination | 도깨비(23) · 유니콘(21) | 나비(22) · 용(24) |

### 6.3 뱃지 연동(`RAILS_PLAN.md` §13.3)
- `first_evolve` 첫 진화 · `final_form` 첫 완전진화 · `dex_half` 도감 절반(12/24) · `dex_complete` 도감 완성(24/24).

---

## 7. 기계 판독용 시드 (YAML)

`db/seeds/monsters.yml`로 추출해 `db/seeds.rb`에서 로드 가능. 규칙:
- 라인당 `forms` 3개(stage 1·2·3). `evolves_from_id`는 **stage 순서로 자동 연결**(시더가 이전 stage를 부모로 설정).
- `evolve_condition`은 **해당 폼에서 다음 단계로 가는 조건**(§6.2 스키마와 동일). stage 3은 조건 없음.
- `starter: true`인 라인의 stage 1이 스타터 선택지. `phase: 1`은 Phase 1 시드 대상.

```yaml
monster_lines:
  # === STORY (보라) ===
  - dex_no: 1
    element: story
    rarity: common
    starter: true
    phase: 1
    forms:
      - { stage: 1, key: pup_1, name: "갈피멍", evolve_condition: { points: 100, reports: 3 } }
      - { stage: 2, key: pup_2, name: "이야기멍", evolve_condition: { points: 450, a_grades: 1, b_or_better: 5 } }
      - { stage: 3, key: pup_3, name: "전설멍" }
  - dex_no: 2
    element: story
    rarity: rare
    phase: 1
    forms:
      - { stage: 1, key: parrot_1, name: "쫑알이", evolve_condition: { points: 100, reports: 5 } }
      - { stage: 2, key: parrot_2, name: "수다앵무", evolve_condition: { points: 700, reports: 12, a_grades: 2 } }
      - { stage: 3, key: parrot_3, name: "이야기봉황" }
  - dex_no: 3
    element: story
    rarity: common
    phase: 2
    forms:
      - { stage: 1, key: pencil_1, name: "뾰족이", evolve_condition: { points: 150, topic_posts: 2 } }
      - { stage: 2, key: pencil_2, name: "또각연필", evolve_condition: { points: 450, a_grades: 2 } }
      - { stage: 3, key: pencil_3, name: "글씨봉" }
  - dex_no: 4
    element: story
    rarity: rare
    phase: 2
    forms:
      - { stage: 1, key: fox_1, name: "도담여우", evolve_condition: { points: 150, distinct_genres: 2 } }
      - { stage: 2, key: fox_2, name: "이야기여우", evolve_condition: { points: 700, classics: 1, reports: 8 } }
      - { stage: 3, key: fox_3, name: "만담여우" }

  # === KNOWLEDGE (파랑) ===
  - dex_no: 5
    element: knowledge
    rarity: common
    starter: true
    phase: 1
    forms:
      - { stage: 1, key: cat_1, name: "아롱냥", evolve_condition: { points: 100, distinct_genres: 2 } }
      - { stage: 2, key: cat_2, name: "안경냥", evolve_condition: { points: 450, distinct_genres: 4 } }
      - { stage: 3, key: cat_3, name: "지혜냥" }
  - dex_no: 6
    element: knowledge
    rarity: common
    phase: 1
    forms:
      - { stage: 1, key: owl_1, name: "동글부엉", evolve_condition: { points: 100, quizzes: 3 } }
      - { stage: 2, key: owl_2, name: "반짝부엉", evolve_condition: { points: 450, quizzes: 8, a_grades: 1 } }
      - { stage: 3, key: owl_3, name: "아이디어부엉" }
  - dex_no: 7
    element: knowledge
    rarity: rare
    phase: 2
    forms:
      - { stage: 1, key: robot_1, name: "도르리", evolve_condition: { points: 150, missions: 1 } }
      - { stage: 2, key: robot_2, name: "째깍로봇", evolve_condition: { points: 700, distinct_genres: 5, quizzes: 5 } }
      - { stage: 3, key: robot_3, name: "발명로봇" }
  - dex_no: 8
    element: knowledge
    rarity: epic
    phase: 2
    forms:
      - { stage: 1, key: turtle_1, name: "조각등", evolve_condition: { points: 250, classics: 1 } }
      - { stage: 2, key: turtle_2, name: "지식거북", evolve_condition: { points: 1000, classics: 3, distinct_genres: 5 } }
      - { stage: 3, key: turtle_3, name: "만물거북" }

  # === EMOTION (분홍) ===
  - dex_no: 9
    element: emotion
    rarity: common
    unlock_candidate: true
    phase: 1
    forms:
      - { stage: 1, key: hamster_1, name: "콩닥이", evolve_condition: { points: 100, reports: 3 } }
      - { stage: 2, key: hamster_2, name: "두근이", evolve_condition: { points: 450, a_grades: 2 } }
      - { stage: 3, key: hamster_3, name: "사랑햄둥이" }
  - dex_no: 10
    element: emotion
    rarity: common
    phase: 1
    forms:
      - { stage: 1, key: whale_1, name: "또르고래", evolve_condition: { points: 100, b_or_better: 3 } }
      - { stage: 2, key: whale_2, name: "촉촉고래", evolve_condition: { points: 450, a_grades: 3 } }
      - { stage: 3, key: whale_3, name: "무지개고래" }
  - dex_no: 11
    element: emotion
    rarity: rare
    phase: 2
    forms:
      - { stage: 1, key: rabbit_1, name: "몽실토끼", evolve_condition: { points: 150, cheers_received: 5 } }
      - { stage: 2, key: rabbit_2, name: "뭉게토끼", evolve_condition: { points: 700, a_grades: 3, cheers_received: 15 } }
      - { stage: 3, key: rabbit_3, name: "노을토끼" }
  - dex_no: 12
    element: emotion
    rarity: common
    phase: 2
    forms:
      - { stage: 1, key: deer_1, name: "새싹사슴", evolve_condition: { points: 100, reports: 4 } }
      - { stage: 2, key: deer_2, name: "꽃봉사슴", evolve_condition: { points: 450, a_grades: 2, revisions: 1 } }
      - { stage: 3, key: deer_3, name: "만개사슴" }

  # === ADVENTURE (주황) ===
  - dex_no: 13
    element: adventure
    rarity: common
    unlock_candidate: true
    phase: 1
    forms:
      - { stage: 1, key: bear_1, name: "방향곰", evolve_condition: { points: 100, missions: 1 } }
      - { stage: 2, key: bear_2, name: "탐험곰", evolve_condition: { points: 450, streak_days: 5, missions: 2 } }
      - { stage: 3, key: bear_3, name: "곰선장" }
  - dex_no: 14
    element: adventure
    rarity: common
    phase: 1
    forms:
      - { stage: 1, key: chick_1, name: "반디병아리", evolve_condition: { points: 100, streak_days: 3 } }
      - { stage: 2, key: chick_2, name: "활활닭", evolve_condition: { points: 700, streak_days: 7 } }
      - { stage: 3, key: chick_3, name: "불꽃장닭" }
  - dex_no: 15
    element: adventure
    rarity: rare
    phase: 2
    forms:
      - { stage: 1, key: penguin_1, name: "붕붕펭", evolve_condition: { points: 150, quizzes: 3 } }
      - { stage: 2, key: penguin_2, name: "슝슝펭", evolve_condition: { points: 700, streak_days: 10, challenges: 1 } }
      - { stage: 3, key: penguin_3, name: "은하펭선장" }
  - dex_no: 16
    element: adventure
    rarity: rare
    phase: 2
    forms:
      - { stage: 1, key: dino_1, name: "알록공", evolve_condition: { points: 150, reports: 5 } }
      - { stage: 2, key: dino_2, name: "티라돌", evolve_condition: { points: 700, missions: 3, streak_days: 7 } }
      - { stage: 3, key: dino_3, name: "모험왕티라노" }

  # === NATURE (초록) ===
  - dex_no: 17
    element: nature
    rarity: common
    starter: true
    phase: 1
    forms:
      - { stage: 1, key: hedgehog_1, name: "새싹도치", evolve_condition: { points: 100, reports: 3 } }
      - { stage: 2, key: hedgehog_2, name: "잎사귀도치", evolve_condition: { points: 450, revisions: 1, reports: 8 } }
      - { stage: 3, key: hedgehog_3, name: "숲지기도치" }
  - dex_no: 18
    element: nature
    rarity: common
    phase: 1
    forms:
      - { stage: 1, key: frog_1, name: "퐁당올챙", evolve_condition: { points: 100, reports: 4 } }
      - { stage: 2, key: frog_2, name: "시냇개구리", evolve_condition: { points: 450, revisions: 2 } }
      - { stage: 3, key: frog_3, name: "개굴대왕" }
  - dex_no: 19
    element: nature
    rarity: common
    phase: 2
    forms:
      - { stage: 1, key: squirrel_1, name: "도토리", evolve_condition: { points: 100, missions: 1 } }
      - { stage: 2, key: squirrel_2, name: "볼록이", evolve_condition: { points: 450, distinct_genres: 3, reports: 8 } }
      - { stage: 3, key: squirrel_3, name: "숲요정다래" }
  - dex_no: 20
    element: nature
    rarity: rare
    phase: 2
    forms:
      - { stage: 1, key: mushroom_1, name: "몽글버섯", evolve_condition: { points: 150, streak_days: 3 } }
      - { stage: 2, key: mushroom_2, name: "우산버섯", evolve_condition: { points: 700, revisions: 2, streak_days: 7 } }
      - { stage: 3, key: mushroom_3, name: "신비버섯" }

  # === IMAGINATION (무지개/금) ===
  - dex_no: 21
    element: imagination
    rarity: rare
    unlock_candidate: true
    phase: 1
    forms:
      - { stage: 1, key: unicorn_1, name: "꼬마유니콘", evolve_condition: { points: 150, quizzes: 3 } }
      - { stage: 2, key: unicorn_2, name: "꿈별유니콘", evolve_condition: { points: 700, dex_count: 5, a_grades: 2 } }
      - { stage: 3, key: unicorn_3, name: "별자리유니콘" }
  - dex_no: 22
    element: imagination
    rarity: rare
    phase: 2
    forms:
      - { stage: 1, key: butterfly_1, name: "물감애벌레", evolve_condition: { points: 150, distinct_genres: 3 } }
      - { stage: 2, key: butterfly_2, name: "무지개고치", evolve_condition: { points: 700, dex_count: 6, revisions: 1 } }
      - { stage: 3, key: butterfly_3, name: "무지개나비" }
  - dex_no: 23
    element: imagination
    rarity: common
    phase: 1
    forms:
      - { stage: 1, key: dokkaebi_1, name: "방울깨비", evolve_condition: { points: 100, quizzes: 3 } }
      - { stage: 2, key: dokkaebi_2, name: "뿔깨비", evolve_condition: { points: 450, dex_count: 4, missions: 2 } }
      - { stage: 3, key: dokkaebi_3, name: "무쌍깨비" }
  - dex_no: 24
    element: imagination
    rarity: epic
    phase: 2
    forms:
      - { stage: 1, key: dragon_1, name: "알드래", evolve_condition: { points: 250, dex_count: 5 } }
      - { stage: 2, key: dragon_2, name: "뭉치용", evolve_condition: { points: 1000, dex_count: 10, a_grades: 3, classics: 2 } }
      - { stage: 3, key: dragon_3, name: "상상용" }
```

---

### 참고
- 스키마·진화 엔진: `RAILS_PLAN.md` §6.2(monster_species/user_monsters), §13.5(도감·진화 규칙).
- 이미지 제작: §3 아트 스타일 바이블(마스터 프롬프트 + 속성 팔레트 + 네거티브).
