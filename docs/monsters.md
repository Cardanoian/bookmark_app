# 「책갈피」 반려 몬스터 도감 시드 설계서

> **목적**: `RAILS_PLAN.md` §13.5(반려 몬스터 도감·진화)의 **실제 콘텐츠 시드**. 아바타를 대체하는 수집형 반려 몬스터의 종·진화 라인·진화 조건·AI 이미지 생성 가이드를 착수 가능한 수준으로 정의한다.
>
> 대상: 초등 5~6학년. 포켓몬스터·디지몬처럼 아이들이 좋아할 다양한 크리처를 담되 **완전 오리지널**(기존 IP 모방 금지 — 법적·대회 리스크).
> 최종 수정: 2026-07-04

---

## 1. 개요

- **규모**: 진화 라인 **24개**(6속성 × 4계열), 각 라인 **3단계**(기본형 → 성장형 → 완전형) = **72폼**.
- **수집(도감) 방식**: 학생마다 도감을 채워 나감. 첫 **스타터 1종 선택**(서로 다른 속성 후보 중), 이후 트레이너 레벨업·챌린지·뱃지 등 **마일스톤마다 신규 몬스터 발견**(가챠 없음).
- **진화**: 포인트 임계 **+ 독서 행동 조건** 조합. 라인마다 성격이 달라 서로 다른 독서 습관을 유도한다(§4, §5).
- **에셋 물량 관리**: **Phase 1은 12라인(36폼)만 시드**(§6), 이후 24라인으로 확장.
- 이 문서의 각 항목은 `monster_species` 스키마(dex_no·stage·key·name·element·rarity·evolves_from·evolve_condition·image_key·description)에 1:1 매핑된다.

---

## 2. 6속성 체계

각 속성은 유도하려는 독서 습관과 시각 톤을 가진다.

| 속성(element) | 한글 | 대표색 | 성격 | 진화가 유도하는 독서 습관 |
|------|------|--------|------|-----------|
| `story` | 이야기 | 보라 | 이야기·글쓰기 | 꾸준한 독후감 작성·표현·토론 |
| `knowledge` | 지식 | 파랑 | 지혜·탐구 | 다양한 장르·고전·퀴즈·탐구 |
| `emotion` | 감성 | 분홍 | 마음·공감 | 감상 표현·삶과 연결(A등급)·응원 |
| `adventure` | 모험 | 주황 | 용기·도전 | 연속 독서 스트릭·미션·챌린지 |
| `nature` | 자연 | 초록 | 성실·성장 | 성실한 활동·고쳐쓰기·성장 |
| `imagination` | 상상 | 무지개/금 | 창의·종합 | 도감 수집·창의 활동·종합 성취(최고난도) |

> **질 우선 정렬**: 완전형(3단계) 조건에 A등급·삶과 연결·고전·고쳐쓰기·도감 수집 등을 배치해, 게임화가 `RAILS_PLAN.md` §1.3 "발전적 첨삭" 가치와 정렬되도록 한다.

---

## 3. 아트 스타일 바이블 (AI 이미지 생성 공통 가이드)

72폼을 서로 다른 AI 이미지로 만들되 **하나의 도감처럼 통일**되어야 한다. 아래 규칙을 모든 이미지에 공통 적용한다.

### 3.1 공통 스펙
- **스타일**: 부드러운 셀 셰이딩(soft cel-shading), **굵고 깔끔한 외곽선**, 파스텔+비비드 혼합, 아동친화 마스코트 톤.
- **비례**: 마스코트형 통일 실루엣. 요정·인간형은 앱 캐릭터와 동일한 **5등신** 비례, 동물·블롭형은 둥글고 큰 머리의 치비 실루엣.
- **포즈/구도**: 정면 3/4, 전신, 중앙 정렬, 밝은 상단 조명, 큰 눈·또렷한 표정.
- **캔버스**: 정사각형 1024×1024, **배경 투명 PNG**(그림자 없음 또는 아주 옅은 접지 그림자 옵션).
- **금지**: 텍스트·워터마크·서명·로고, 배경 장식, 기존 캐릭터(포켓몬/디지몬/기타 IP) 유사.
- **파일**: `image_key` = 슬러그(예: `galpi_1`) → `app/assets/images/monsters/galpi_1.png`(또는 Active Storage 키).

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
- **galpi_1 (갈피씨)**:
  `A cute original creature mascot for a children's reading app, "a tiny seed-shaped fairy baby with a bookmark-ribbon tail and big round eyes", violet lavender cream color palette, soft cel-shading, thick clean outlines, big expressive eyes, chibi proportions, front three-quarter full-body view, centered, soft top lighting, flat transparent background, sticker-style, original design.`
- **owl_2 (안경부엉)**:
  `... "a small round owl wearing tiny round glasses, fluffy feathers", blue teal silver color palette, ... 5-head-tall chibi proportions ...`
- **dreamdragon_3 (상상의대룡)**:
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
| `streak_days` | 연속 독서일(마라톤) | 마라톤 게임/제출 스트릭 |
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
| 1 | 갈피 ★스타터 | common | 1 | `galpi_1` | 갈피씨 | 씨앗 몸통 + 책갈피 리본 꼬리의 아기 요정 |
| 1 | 갈피 | common | 2 | `galpi_2` | 갈피요 | 작은 책을 품에 안은 요정, 리본이 커짐 |
| 1 | 갈피 | common | 3 | `galpi_3` | 갈피별 | 빛나는 책 날개·별빛 리본의 수호 요정 |
| 2 | 이야기룡 | rare | 1 | `storydragon_1` | 글송이 | 책장 사이 글자 무늬 통통 애벌레 |
| 2 | 이야기룡 | rare | 2 | `storydragon_2` | 책누에 | 책 모양 고치를 두른 번데기 |
| 2 | 이야기룡 | rare | 3 | `storydragon_3` | 이야기룡 | 펼친 책장 날개의 작은 용 |
| 3 | 잉크 | common | 1 | `ink_1` | 잉크똑 | 동글동글 잉크 방울 정령 |
| 3 | 잉크 | common | 2 | `ink_2` | 붓여울 | 붓 꼬리를 단 여우 정령 |
| 3 | 잉크 | common | 3 | `ink_3` | 글빛봉 | 글씨가 빛나는 붓 깃털 봉황 |
| 4 | 옛이야기 | rare | 1 | `oldtale_1` | 도담이 | 표지에 눈이 달린 옛날이야기 아기책 |
| 4 | 옛이야기 | rare | 2 | `oldtale_2` | 재잘책 | 팔이 생긴 수다스러운 펼친 책 |
| 4 | 옛이야기 | rare | 3 | `oldtale_3` | 만권신선 | 두루마리를 두른 수염 신선 책 |

| dex | 계열 | 1→2 조건 | 2→3 조건 |
|----|------|----------|----------|
| 1 | 갈피 | `points:100, reports:3` | `points:450, a_grades:1, b_or_better:5` |
| 2 | 이야기룡 | `points:100, reports:5` | `points:700, reports:12, a_grades:2` |
| 3 | 잉크 | `points:150, topic_posts:2` | `points:450, a_grades:2` |
| 4 | 옛이야기 | `points:150, distinct_genres:2` | `points:700, classics:1, reports:8` |

### 5.2 지식 (KNOWLEDGE) — dex 5~8 · 파랑

| dex | 계열 | 등급 | 단계 | key | 이름 | 이미지 주제 |
|----|------|------|------|-----|------|-------------|
| 5 | 부엉이 ★스타터 | common | 1 | `owl_1` | 아롱부엉 | 큰 눈의 동글 아기 부엉이 |
| 5 | 부엉이 | common | 2 | `owl_2` | 안경부엉 | 동그란 안경을 쓴 부엉이 |
| 5 | 부엉이 | common | 3 | `owl_3` | 지혜부엉왕 | 학사모·망토의 현자 부엉이 |
| 6 | 아이디어 | common | 1 | `idea_1` | 반짝알 | 작은 전구 알 정령 |
| 6 | 아이디어 | common | 2 | `idea_2` | 번뜩이 | 번개 뿔이 난 전구 정령 |
| 6 | 아이디어 | common | 3 | `idea_3` | 별똥아이 | 아이디어 별똥별 정령 |
| 7 | 발명 | rare | 1 | `invent_1` | 도르리 | 작은 톱니바퀴 로봇 |
| 7 | 발명 | rare | 2 | `invent_2` | 째깍이 | 태엽·시계 몸통 로봇 |
| 7 | 발명 | rare | 3 | `invent_3` | 발명룡 | 기계 날개의 톱니 용 |
| 8 | 수정 | epic | 1 | `crystal_1` | 조각돌 | 작은 수정 조각 정령 |
| 8 | 수정 | epic | 2 | `crystal_2` | 지식정 | 책 문양 수정 골렘 새끼 |
| 8 | 수정 | epic | 3 | `crystal_3` | 만물박사 | 지식 룬이 새겨진 거대 수정 골렘 |

| dex | 계열 | 1→2 조건 | 2→3 조건 |
|----|------|----------|----------|
| 5 | 부엉이 | `points:100, distinct_genres:2` | `points:450, distinct_genres:4` |
| 6 | 아이디어 | `points:100, quizzes:3` | `points:450, quizzes:8, a_grades:1` |
| 7 | 발명 | `points:150, missions:1` | `points:700, distinct_genres:5, quizzes:5` |
| 8 | 수정 | `points:250, classics:1` | `points:1000, classics:3, distinct_genres:5` |

### 5.3 감성 (EMOTION) — dex 9~12 · 분홍

| dex | 계열 | 등급 | 단계 | key | 이름 | 이미지 주제 |
|----|------|------|------|-----|------|-------------|
| 9 | 하트 ★스타터 | common | 1 | `heart_1` | 콩닥이 | 볼 발그레한 작은 하트 몸통 |
| 9 | 하트 | common | 2 | `heart_2` | 두근이 | 하트 두 개가 겹친 리본 정령 |
| 9 | 하트 | common | 3 | `heart_3` | 사랑둥이 | 큰 하트 날개의 천사 정령 |
| 10 | 눈물 | common | 1 | `tear_1` | 또르방울 | 물방울 눈물 정령 |
| 10 | 눈물 | common | 2 | `tear_2` | 촉촉이 | 눈물 구슬 목걸이의 정령 |
| 10 | 눈물 | common | 3 | `tear_3` | 무지개눈물 | 무지개 눈물의 감동 아기고래 |
| 11 | 기분구름 | rare | 1 | `moodcloud_1` | 몽실 | 표정이 변하는 작은 뭉게구름 |
| 11 | 기분구름 | rare | 2 | `moodcloud_2` | 뭉게 | 무지개를 걸친 구름 |
| 11 | 기분구름 | rare | 3 | `moodcloud_3` | 노을고래 | 노을빛 하늘고래 |
| 12 | 감성꽃 | common | 1 | `bloom_1` | 새싹몽 | 잎 팔이 달린 꽃봉오리 아기 |
| 12 | 감성꽃 | common | 2 | `bloom_2` | 꽃봉오 | 반쯤 핀 꽃 정령 |
| 12 | 감성꽃 | common | 3 | `bloom_3` | 꽃사슴 | 활짝 핀 꽃뿔 사슴 |

| dex | 계열 | 1→2 조건 | 2→3 조건 |
|----|------|----------|----------|
| 9 | 하트 | `points:100, reports:3` | `points:450, a_grades:2` |
| 10 | 눈물 | `points:100, b_or_better:3` | `points:450, a_grades:3` |
| 11 | 기분구름 | `points:150, cheers_received:5` | `points:700, a_grades:3, cheers_received:15` |
| 12 | 감성꽃 | `points:100, reports:4` | `points:450, a_grades:2, revisions:1` |

### 5.4 모험 (ADVENTURE) — dex 13~16 · 주황

| dex | 계열 | 등급 | 단계 | key | 이름 | 이미지 주제 |
|----|------|------|------|-----|------|-------------|
| 13 | 나침반 ★스타터 | common | 1 | `compass_1` | 방향돌이 | 나침반 몸통의 아기 정령 |
| 13 | 나침반 | common | 2 | `compass_2` | 탐험모자 | 탐험가 모자·배낭을 멘 아기곰 |
| 13 | 나침반 | common | 3 | `compass_3` | 곰선장 | 망토·깃발을 든 대탐험가 곰 |
| 14 | 불꽃 | common | 1 | `flame_1` | 반디불 | 반딧불 같은 작은 불씨 정령 |
| 14 | 불꽃 | common | 2 | `flame_2` | 활활이 | 불꽃 갈기의 여우 |
| 14 | 불꽃 | common | 3 | `flame_3` | 불사조 | 용감한 아기 불사조 |
| 15 | 우주 | rare | 1 | `rocket_1` | 붕붕별 | 작은 별 로켓 |
| 15 | 우주 | rare | 2 | `rocket_2` | 슝슝이 | 로켓 등딱지를 멘 거북 |
| 15 | 우주 | rare | 3 | `rocket_3` | 은하룡 | 은하 꼬리의 우주 용 |
| 16 | 공룡 | rare | 1 | `dino_1` | 알록공 | 알록달록 알에서 반쯤 나온 아기 공룡 |
| 16 | 공룡 | rare | 2 | `dino_2` | 티라돌 | 탐험 손수건을 두른 작은 티라노 |
| 16 | 공룡 | rare | 3 | `dino_3` | 모험왕티라노 | 갑옷을 두른 용맹한 티라노 |

| dex | 계열 | 1→2 조건 | 2→3 조건 |
|----|------|----------|----------|
| 13 | 나침반 | `points:100, missions:1` | `points:450, streak_days:5, missions:2` |
| 14 | 불꽃 | `points:100, streak_days:3` | `points:700, streak_days:7` |
| 15 | 우주 | `points:150, quizzes:3` | `points:700, streak_days:10, challenges:1` |
| 16 | 공룡 | `points:150, reports:5` | `points:700, missions:3, streak_days:7` |

### 5.5 자연 (NATURE) — dex 17~20 · 초록

| dex | 계열 | 등급 | 단계 | key | 이름 | 이미지 주제 |
|----|------|------|------|-----|------|-------------|
| 17 | 새싹 ★스타터 | common | 1 | `sprout_1` | 새싹콩 | 흙에서 갓 난 콩 얼굴 새싹 |
| 17 | 새싹 | common | 2 | `sprout_2` | 잎사귀 | 잎사귀 망토의 새싹 정령 |
| 17 | 새싹 | common | 3 | `sprout_3` | 숲지기 | 작은 나무 몸통의 숲 정령 |
| 18 | 물 | common | 1 | `water_1` | 퐁당이 | 물방울 올챙이 |
| 18 | 물 | common | 2 | `water_2` | 시냇이 | 시냇물 아기 수달 |
| 18 | 물 | common | 3 | `water_3` | 강물신 | 강을 다스리는 수달신 |
| 19 | 다람쥐 | common | 1 | `squirrel_1` | 도토리 | 도토리를 안은 아기 다람쥐 |
| 19 | 다람쥐 | common | 2 | `squirrel_2` | 볼록이 | 볼이 빵빵한 다람쥐 |
| 19 | 다람쥐 | common | 3 | `squirrel_3` | 숲요정다래 | 나뭇잎 왕관의 다람쥐 요정 |
| 20 | 버섯 | rare | 1 | `mushroom_1` | 몽글버섯 | 작은 버섯 정령 |
| 20 | 버섯 | rare | 2 | `mushroom_2` | 우산버섯 | 우산을 쓴 버섯 |
| 20 | 버섯 | rare | 3 | `mushroom_3` | 신비버섯 | 빛나는 포자의 신비 버섯 정령 |

| dex | 계열 | 1→2 조건 | 2→3 조건 |
|----|------|----------|----------|
| 17 | 새싹 | `points:100, reports:3` | `points:450, revisions:1, reports:8` |
| 18 | 물 | `points:100, reports:4` | `points:450, revisions:2` |
| 19 | 다람쥐 | `points:100, missions:1` | `points:450, distinct_genres:3, reports:8` |
| 20 | 버섯 | `points:150, streak_days:3` | `points:700, revisions:2, streak_days:7` |

### 5.6 상상 (IMAGINATION) — dex 21~24 · 무지개/금

| dex | 계열 | 등급 | 단계 | key | 이름 | 이미지 주제 |
|----|------|------|------|-----|------|-------------|
| 21 | 별유니콘 ★스타터 | rare | 1 | `star_1` | 꼬마별 | 반짝이는 작은 별 정령 |
| 21 | 별유니콘 | rare | 2 | `star_2` | 꿈별이 | 별 갈기의 아기 유니콘 |
| 21 | 별유니콘 | rare | 3 | `star_3` | 별자리유니콘 | 별자리 갈기의 유니콘 |
| 22 | 무지개붓 | rare | 1 | `rainbow_1` | 물감똑 | 알록달록 물감 방울 |
| 22 | 무지개붓 | rare | 2 | `rainbow_2` | 색동이 | 무지개 붓꼬리 새 |
| 22 | 무지개붓 | rare | 3 | `rainbow_3` | 무지개붓새 | 무지개 깃털의 붓새 |
| 23 | 도깨비 | common | 1 | `dokkaebi_1` | 방울도깨비 | 작은 뿔·방망이의 아기 도깨비 |
| 23 | 도깨비 | common | 2 | `dokkaebi_2` | 뿔도깨비 | 뿔이 커진 장난꾸러기 도깨비 |
| 23 | 도깨비 | common | 3 | `dokkaebi_3` | 도깨비대장 | 금방망이를 든 도깨비 대장 |
| 24 | 상상용 | epic | 1 | `dreamdragon_1` | 알드래 | 무지개 용알에서 나온 아기 |
| 24 | 상상용 | epic | 2 | `dreamdragon_2` | 뭉치용 | 구름 같은 몸의 새끼 용 |
| 24 | 상상용 | epic | 3 | `dreamdragon_3` | 상상의대룡 | 무지갯빛 거대한 상상의 용 |

| dex | 계열 | 1→2 조건 | 2→3 조건 |
|----|------|----------|----------|
| 21 | 별유니콘 | `points:150, quizzes:3` | `points:700, dex_count:5, a_grades:2` |
| 22 | 무지개붓 | `points:150, distinct_genres:3` | `points:700, dex_count:6, revisions:1` |
| 23 | 도깨비 | `points:100, quizzes:3` | `points:450, dex_count:4, missions:2` |
| 24 | 상상용 | epic | `points:250, dex_count:5` | `points:1000, dex_count:10, a_grades:3, classics:2` |

---

## 6. 스타터 & Phase 1 시드

### 6.1 스타터(첫 선택 3종)
서로 다른 속성·분위기로 균형: 학생이 가입 직후 1종 선택.
- `galpi_1` **갈피씨**(story, 포근한 마스코트 — 브랜드 상징)
- `owl_1` **아롱부엉**(knowledge, 똑똑 귀여움)
- `sprout_1` **새싹콩**(nature, 옛 성장단계 오마주)

> 별유니콘(`star_1`)·나침반(`compass_1`)·콩닥이(`heart_1`)는 초반 마일스톤 해금 후보로 두어 선택지 다양성 확보.

### 6.2 Phase 1 시드(12라인 = 36폼)
에셋 물량을 고려해 각 속성 대표 2라인부터 제작·시드.

| 속성 | Phase 1 라인 |
|------|--------------|
| story | 갈피(1) · 이야기룡(2) |
| knowledge | 부엉이(5) · 아이디어(6) |
| emotion | 하트(9) · 눈물(10) |
| adventure | 나침반(13) · 불꽃(14) |
| nature | 새싹(17) · 물(18) |
| imagination | 도깨비(23) · 별유니콘(21) |

Phase 2에서 나머지 12라인(잉크·옛이야기·발명·수정·기분구름·감성꽃·우주·공룡·다람쥐·버섯·무지개붓·상상용) 확장.

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
      - { stage: 1, key: galpi_1, name: "갈피씨", evolve_condition: { points: 100, reports: 3 } }
      - { stage: 2, key: galpi_2, name: "갈피요", evolve_condition: { points: 450, a_grades: 1, b_or_better: 5 } }
      - { stage: 3, key: galpi_3, name: "갈피별" }
  - dex_no: 2
    element: story
    rarity: rare
    phase: 1
    forms:
      - { stage: 1, key: storydragon_1, name: "글송이", evolve_condition: { points: 100, reports: 5 } }
      - { stage: 2, key: storydragon_2, name: "책누에", evolve_condition: { points: 700, reports: 12, a_grades: 2 } }
      - { stage: 3, key: storydragon_3, name: "이야기룡" }
  - dex_no: 3
    element: story
    rarity: common
    forms:
      - { stage: 1, key: ink_1, name: "잉크똑", evolve_condition: { points: 150, topic_posts: 2 } }
      - { stage: 2, key: ink_2, name: "붓여울", evolve_condition: { points: 450, a_grades: 2 } }
      - { stage: 3, key: ink_3, name: "글빛봉" }
  - dex_no: 4
    element: story
    rarity: rare
    forms:
      - { stage: 1, key: oldtale_1, name: "도담이", evolve_condition: { points: 150, distinct_genres: 2 } }
      - { stage: 2, key: oldtale_2, name: "재잘책", evolve_condition: { points: 700, classics: 1, reports: 8 } }
      - { stage: 3, key: oldtale_3, name: "만권신선" }

  # === KNOWLEDGE (파랑) ===
  - dex_no: 5
    element: knowledge
    rarity: common
    starter: true
    phase: 1
    forms:
      - { stage: 1, key: owl_1, name: "아롱부엉", evolve_condition: { points: 100, distinct_genres: 2 } }
      - { stage: 2, key: owl_2, name: "안경부엉", evolve_condition: { points: 450, distinct_genres: 4 } }
      - { stage: 3, key: owl_3, name: "지혜부엉왕" }
  - dex_no: 6
    element: knowledge
    rarity: common
    phase: 1
    forms:
      - { stage: 1, key: idea_1, name: "반짝알", evolve_condition: { points: 100, quizzes: 3 } }
      - { stage: 2, key: idea_2, name: "번뜩이", evolve_condition: { points: 450, quizzes: 8, a_grades: 1 } }
      - { stage: 3, key: idea_3, name: "별똥아이" }
  - dex_no: 7
    element: knowledge
    rarity: rare
    forms:
      - { stage: 1, key: invent_1, name: "도르리", evolve_condition: { points: 150, missions: 1 } }
      - { stage: 2, key: invent_2, name: "째깍이", evolve_condition: { points: 700, distinct_genres: 5, quizzes: 5 } }
      - { stage: 3, key: invent_3, name: "발명룡" }
  - dex_no: 8
    element: knowledge
    rarity: epic
    forms:
      - { stage: 1, key: crystal_1, name: "조각돌", evolve_condition: { points: 250, classics: 1 } }
      - { stage: 2, key: crystal_2, name: "지식정", evolve_condition: { points: 1000, classics: 3, distinct_genres: 5 } }
      - { stage: 3, key: crystal_3, name: "만물박사" }

  # === EMOTION (분홍) ===
  - dex_no: 9
    element: emotion
    rarity: common
    unlock_candidate: true
    phase: 1
    forms:
      - { stage: 1, key: heart_1, name: "콩닥이", evolve_condition: { points: 100, reports: 3 } }
      - { stage: 2, key: heart_2, name: "두근이", evolve_condition: { points: 450, a_grades: 2 } }
      - { stage: 3, key: heart_3, name: "사랑둥이" }
  - dex_no: 10
    element: emotion
    rarity: common
    phase: 1
    forms:
      - { stage: 1, key: tear_1, name: "또르방울", evolve_condition: { points: 100, b_or_better: 3 } }
      - { stage: 2, key: tear_2, name: "촉촉이", evolve_condition: { points: 450, a_grades: 3 } }
      - { stage: 3, key: tear_3, name: "무지개눈물" }
  - dex_no: 11
    element: emotion
    rarity: rare
    forms:
      - { stage: 1, key: moodcloud_1, name: "몽실", evolve_condition: { points: 150, cheers_received: 5 } }
      - { stage: 2, key: moodcloud_2, name: "뭉게", evolve_condition: { points: 700, a_grades: 3, cheers_received: 15 } }
      - { stage: 3, key: moodcloud_3, name: "노을고래" }
  - dex_no: 12
    element: emotion
    rarity: common
    forms:
      - { stage: 1, key: bloom_1, name: "새싹몽", evolve_condition: { points: 100, reports: 4 } }
      - { stage: 2, key: bloom_2, name: "꽃봉오", evolve_condition: { points: 450, a_grades: 2, revisions: 1 } }
      - { stage: 3, key: bloom_3, name: "꽃사슴" }

  # === ADVENTURE (주황) ===
  - dex_no: 13
    element: adventure
    rarity: common
    unlock_candidate: true
    phase: 1
    forms:
      - { stage: 1, key: compass_1, name: "방향돌이", evolve_condition: { points: 100, missions: 1 } }
      - { stage: 2, key: compass_2, name: "탐험모자", evolve_condition: { points: 450, streak_days: 5, missions: 2 } }
      - { stage: 3, key: compass_3, name: "곰선장" }
  - dex_no: 14
    element: adventure
    rarity: common
    phase: 1
    forms:
      - { stage: 1, key: flame_1, name: "반디불", evolve_condition: { points: 100, streak_days: 3 } }
      - { stage: 2, key: flame_2, name: "활활이", evolve_condition: { points: 700, streak_days: 7 } }
      - { stage: 3, key: flame_3, name: "불사조" }
  - dex_no: 15
    element: adventure
    rarity: rare
    forms:
      - { stage: 1, key: rocket_1, name: "붕붕별", evolve_condition: { points: 150, quizzes: 3 } }
      - { stage: 2, key: rocket_2, name: "슝슝이", evolve_condition: { points: 700, streak_days: 10, challenges: 1 } }
      - { stage: 3, key: rocket_3, name: "은하룡" }
  - dex_no: 16
    element: adventure
    rarity: rare
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
      - { stage: 1, key: sprout_1, name: "새싹콩", evolve_condition: { points: 100, reports: 3 } }
      - { stage: 2, key: sprout_2, name: "잎사귀", evolve_condition: { points: 450, revisions: 1, reports: 8 } }
      - { stage: 3, key: sprout_3, name: "숲지기" }
  - dex_no: 18
    element: nature
    rarity: common
    phase: 1
    forms:
      - { stage: 1, key: water_1, name: "퐁당이", evolve_condition: { points: 100, reports: 4 } }
      - { stage: 2, key: water_2, name: "시냇이", evolve_condition: { points: 450, revisions: 2 } }
      - { stage: 3, key: water_3, name: "강물신" }
  - dex_no: 19
    element: nature
    rarity: common
    forms:
      - { stage: 1, key: squirrel_1, name: "도토리", evolve_condition: { points: 100, missions: 1 } }
      - { stage: 2, key: squirrel_2, name: "볼록이", evolve_condition: { points: 450, distinct_genres: 3, reports: 8 } }
      - { stage: 3, key: squirrel_3, name: "숲요정다래" }
  - dex_no: 20
    element: nature
    rarity: rare
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
      - { stage: 1, key: star_1, name: "꼬마별", evolve_condition: { points: 150, quizzes: 3 } }
      - { stage: 2, key: star_2, name: "꿈별이", evolve_condition: { points: 700, dex_count: 5, a_grades: 2 } }
      - { stage: 3, key: star_3, name: "별자리유니콘" }
  - dex_no: 22
    element: imagination
    rarity: rare
    forms:
      - { stage: 1, key: rainbow_1, name: "물감똑", evolve_condition: { points: 150, distinct_genres: 3 } }
      - { stage: 2, key: rainbow_2, name: "색동이", evolve_condition: { points: 700, dex_count: 6, revisions: 1 } }
      - { stage: 3, key: rainbow_3, name: "무지개붓새" }
  - dex_no: 23
    element: imagination
    rarity: common
    phase: 1
    forms:
      - { stage: 1, key: dokkaebi_1, name: "방울도깨비", evolve_condition: { points: 100, quizzes: 3 } }
      - { stage: 2, key: dokkaebi_2, name: "뿔도깨비", evolve_condition: { points: 450, dex_count: 4, missions: 2 } }
      - { stage: 3, key: dokkaebi_3, name: "도깨비대장" }
  - dex_no: 24
    element: imagination
    rarity: epic
    forms:
      - { stage: 1, key: dreamdragon_1, name: "알드래", evolve_condition: { points: 250, dex_count: 5 } }
      - { stage: 2, key: dreamdragon_2, name: "뭉치용", evolve_condition: { points: 1000, dex_count: 10, a_grades: 3, classics: 2 } }
      - { stage: 3, key: dreamdragon_3, name: "상상의대룡" }
```

---

### 참고
- 스키마·진화 엔진: `RAILS_PLAN.md` §6.2(monster_species/user_monsters), §13.5(도감·진화 규칙).
- 이미지 제작: §3 아트 스타일 바이블(마스터 프롬프트 + 속성 팔레트 + 네거티브).
