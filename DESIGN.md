---
version: alpha
name: Chaekgalpi-design-system
description: 「책갈피」는 초등학교 전학년 독후감·독서 습관 플랫폼으로, 자신감 있고 다정한 브랜드 보이스를 가진다 — 따뜻한 중립 페이지 위 흰 카드와 시그니처 카나리아 옐로({colors.brand-yellow}) 워드마크가 중심을 잡고, 실제 반려 몬스터 도감의 6속성 색을 반영한 파스텔 피처 틴트(로즈·틸·코랄·옐로·민트·라벤더)가 게이미피케이션 화면에 리듬을 준다. 학생의 시작·참여 행동은 옐로, 저장·제출·교직원 주요 행동과 정보성 도구 행동은 블루 필, 보조·이동 행동은 연파랑 필로 구분하며, 5역할(학생·담임·교무·사서·총괄) 표면을 하나의 토큰 체계로 지원한다. 모든 타이포는 한국어 폰트 Pretendard 기반(self-host).

colors:
  primary: "#1c1c1e"
  on-primary: "#ffffff"
  brand-yellow: "#ffd02f"
  brand-yellow-deep: "#fcb900"
  yellow-light: "#fff4c4"
  yellow-dark: "#746019"
  brand-blue: "#4262ff"
  blue-450: "#5b76fe"
  blue-pressed: "#2a41b6"
  blue-soft: "#e8ecff"
  blue-soft-deep: "#d9e0ff"
  blue-soft-pressed: "#cad3ff"
  brand-coral: "#ff9999"
  coral-light: "#ffc6c6"
  coral-dark: "#600000"
  brand-rose: "#ffd8f4"
  rose-light: "#fde0f0"
  brand-pink: "#fde0f0"
  brand-teal: "#0fbcb0"
  teal-light: "#c3faf5"
  moss-dark: "#187574"
  brand-orange-light: "#ffe6cd"
  brand-red: "#fbd4d4"
  brand-red-dark: "#e3c5c5"
  success-accent: "#00b473"
  danger: "#e11d48"
  error-text: "#be123c"
  success-surface: "#ecfdf5"
  success-ink: "#05603a"
  page: "#f7f7f3"
  canvas: "#ffffff"
  surface: "#f7f8fa"
  surface-soft: "#fafbfc"
  surface-yellow: "#fff8e0"
  surface-featured: "#f5f3ff"
  surface-coral: "#fff3e8"
  surface-mint: "#ecfaf7"
  hairline: "#e0e2e8"
  hairline-soft: "#eef0f3"
  hairline-strong: "#c7cad5"
  ink-deep: "#050038"
  ink: "#1c1c1e"
  charcoal: "#2c2c34"
  slate: "#555a6a"
  steel: "#6b6f7e"
  stone: "#8e91a0"
  muted: "#a5a8b5"
  on-dark: "#ffffff"
  on-dark-muted: "#a5a8b5"
  footer-bg: "#1c1c1e"

typography:
  hero-display:
    fontFamily: Pretendard
    fontSize: 80px
    fontWeight: 600
    lineHeight: 1.10
    letterSpacing: -1.5px
  display-lg:
    fontFamily: Pretendard
    fontSize: 60px
    fontWeight: 600
    lineHeight: 1.14
    letterSpacing: -1px
  heading-1:
    fontFamily: Pretendard
    fontSize: 48px
    fontWeight: 600
    lineHeight: 1.20
    letterSpacing: -0.5px
  heading-2:
    fontFamily: Pretendard
    fontSize: 36px
    fontWeight: 600
    lineHeight: 1.25
    letterSpacing: -0.25px
  heading-3:
    fontFamily: Pretendard
    fontSize: 28px
    fontWeight: 600
    lineHeight: 1.30
  heading-4:
    fontFamily: Pretendard
    fontSize: 22px
    fontWeight: 600
    lineHeight: 1.35
  heading-5:
    fontFamily: Pretendard
    fontSize: 18px
    fontWeight: 600
    lineHeight: 1.45
  subtitle:
    fontFamily: Pretendard
    fontSize: 18px
    fontWeight: 400
    lineHeight: 1.60
  body-md:
    fontFamily: Pretendard
    fontSize: 16px
    fontWeight: 400
    lineHeight: 1.60
  body-md-medium:
    fontFamily: Pretendard
    fontSize: 16px
    fontWeight: 500
    lineHeight: 1.60
  body-sm:
    fontFamily: Pretendard
    fontSize: 14px
    fontWeight: 400
    lineHeight: 1.60
  body-sm-medium:
    fontFamily: Pretendard
    fontSize: 14px
    fontWeight: 500
    lineHeight: 1.55
  caption:
    fontFamily: Pretendard
    fontSize: 13px
    fontWeight: 400
    lineHeight: 1.45
  caption-bold:
    fontFamily: Pretendard
    fontSize: 13px
    fontWeight: 600
    lineHeight: 1.45
  micro:
    fontFamily: Pretendard
    fontSize: 12px
    fontWeight: 500
    lineHeight: 1.40
  micro-uppercase:
    fontFamily: Pretendard
    fontSize: 11px
    fontWeight: 600
    lineHeight: 1.40
    letterSpacing: 0.5px
  button-md:
    fontFamily: Pretendard
    fontSize: 15px
    fontWeight: 600
    lineHeight: 1.30
  stat-display:
    fontFamily: Pretendard
    fontSize: 64px
    fontWeight: 700
    lineHeight: 1.10
    letterSpacing: -1px

rounded:
  xs: 4px
  sm: 6px
  md: 8px
  lg: 12px
  xl: 16px
  xxl: 20px
  xxxl: 28px
  feature: 32px
  full: 9999px

spacing:
  xxs: 4px
  xs: 8px
  sm: 12px
  md: 16px
  lg: 20px
  xl: 24px
  xxl: 32px
  xxxl: 40px
  section-sm: 48px
  section: 64px
  section-lg: 96px
  hero: 120px

components:
  button-primary:
    backgroundColor: "{colors.brand-blue}"
    textColor: "{colors.on-primary}"
    typography: "{typography.button-md}"
    rounded: "{rounded.full}"
    padding: "12px 24px"
  button-primary-pressed:
    backgroundColor: "{colors.blue-pressed}"
    textColor: "{colors.on-primary}"
  button-primary-disabled:
    backgroundColor: "{colors.hairline}"
    textColor: "{colors.muted}"
  button-yellow:
    backgroundColor: "{colors.brand-yellow}"
    textColor: "{colors.primary}"
    typography: "{typography.button-md}"
    rounded: "{rounded.full}"
    padding: "12px 24px"
  button-blue:
    backgroundColor: "{colors.brand-blue}"
    textColor: "{colors.on-primary}"
    typography: "{typography.button-md}"
    rounded: "{rounded.full}"
    padding: "12px 24px"
  button-secondary:
    backgroundColor: "{colors.blue-soft}"
    textColor: "{colors.blue-pressed}"
    typography: "{typography.button-md}"
    rounded: "{rounded.full}"
    padding: "12px 24px"
  button-secondary-pressed:
    backgroundColor: "{colors.blue-soft-pressed}"
    textColor: "{colors.blue-pressed}"
  button-on-dark:
    backgroundColor: "{colors.on-dark}"
    textColor: "{colors.primary}"
    typography: "{typography.button-md}"
    rounded: "{rounded.full}"
    padding: "12px 24px"
  button-ghost:
    backgroundColor: "transparent"
    textColor: "{colors.ink}"
    typography: "{typography.button-md}"
    rounded: "{rounded.md}"
    padding: "8px 12px"
  button-link:
    backgroundColor: "transparent"
    textColor: "{colors.brand-blue}"
    typography: "{typography.body-sm-medium}"
    padding: "0"
  button-icon-circular:
    backgroundColor: "{colors.blue-soft}"
    textColor: "{colors.blue-pressed}"
    rounded: "{rounded.full}"
    size: 40px
  card-base:
    backgroundColor: "{colors.canvas}"
    rounded: "{rounded.xl}"
    padding: "{spacing.xl}"
    border: "1px solid {colors.hairline-soft}"
    shadow: "0 1px 2px rgba(5, 0, 56, 0.035), 0 6px 18px rgba(5, 0, 56, 0.025)"
  card-feature:
    backgroundColor: "{colors.canvas}"
    rounded: "{rounded.feature}"
    padding: "{spacing.xxl}"
    border: "1px solid {colors.hairline-soft}"
    shadow: "0 1px 2px rgba(5, 0, 56, 0.035), 0 6px 18px rgba(5, 0, 56, 0.025)"
  card-feature-yellow:
    backgroundColor: "{colors.brand-yellow}"
    textColor: "{colors.primary}"
    rounded: "{rounded.xxxl}"
    padding: "{spacing.xxl}"
  card-feature-coral:
    backgroundColor: "{colors.coral-light}"
    textColor: "{colors.primary}"
    rounded: "{rounded.xxxl}"
    padding: "{spacing.xxl}"
  card-feature-teal:
    backgroundColor: "{colors.teal-light}"
    textColor: "{colors.primary}"
    rounded: "{rounded.xxxl}"
    padding: "{spacing.xxl}"
  card-feature-rose:
    backgroundColor: "{colors.rose-light}"
    textColor: "{colors.primary}"
    rounded: "{rounded.xxxl}"
    padding: "{spacing.xxl}"
  card-story:
    backgroundColor: "{colors.canvas}"
    rounded: "{rounded.xxxl}"
    padding: "0"
    border: "1px solid {colors.hairline-soft}"
  card-stat:
    backgroundColor: "transparent"
    textColor: "{colors.ink}"
    typography: "{typography.stat-display}"
    padding: "{spacing.lg}"
  plan-card:
    backgroundColor: "{colors.canvas}"
    rounded: "{rounded.xl}"
    padding: "{spacing.xxl}"
    border: "1px solid {colors.hairline}"
  plan-card-featured:
    backgroundColor: "{colors.surface-featured}"
    rounded: "{rounded.xl}"
    padding: "{spacing.xxl}"
    border: "2px solid {colors.brand-blue}"
  plan-card-dark:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.on-primary}"
    rounded: "{rounded.xl}"
    padding: "{spacing.xxl}"
  text-input:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    typography: "{typography.body-md}"
    rounded: "{rounded.md}"
    padding: "{spacing.sm} {spacing.md}"
    border: "1px solid {colors.hairline-strong}"
    height: 44px
  text-input-focused:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    border: "2px solid {colors.brand-blue}"
  search-pill:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.steel}"
    typography: "{typography.body-sm}"
    rounded: "{rounded.md}"
    padding: "{spacing.xs} {spacing.md}"
    height: 44px
    border: "1px solid {colors.hairline}"
  filter-dropdown:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    typography: "{typography.body-sm-medium}"
    rounded: "{rounded.full}"
    padding: "{spacing.xs} {spacing.md}"
    border: "1px solid {colors.hairline-strong}"
  pill-tab:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.steel}"
    typography: "{typography.body-sm-medium}"
    rounded: "{rounded.full}"
    padding: "{spacing.xs} {spacing.md}"
    border: "1px solid {colors.hairline}"
  pill-tab-active:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.on-primary}"
    rounded: "{rounded.full}"
    border: "1px solid {colors.primary}"
  toggle-two-state:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    rounded: "{rounded.full}"
    padding: "4px"
  badge-promo:
    backgroundColor: "{colors.brand-yellow}"
    textColor: "{colors.primary}"
    typography: "{typography.caption-bold}"
    rounded: "{rounded.full}"
    padding: "4px 10px"
  badge-tag-yellow:
    backgroundColor: "{colors.surface-yellow}"
    textColor: "{colors.yellow-dark}"
    typography: "{typography.caption-bold}"
    rounded: "{rounded.full}"
    padding: "4px 10px"
  badge-tag-lavender:
    backgroundColor: "{colors.surface-featured}"
    textColor: "{colors.brand-blue}"
    typography: "{typography.caption-bold}"
    rounded: "{rounded.full}"
    padding: "4px 10px"
  badge-tag-coral:
    backgroundColor: "{colors.coral-light}"
    textColor: "{colors.coral-dark}"
    typography: "{typography.caption-bold}"
    rounded: "{rounded.full}"
    padding: "4px 10px"
  badge-success:
    backgroundColor: "{colors.success-accent}"
    textColor: "{colors.on-primary}"
    typography: "{typography.caption-bold}"
    rounded: "{rounded.full}"
    padding: "4px 10px"
  badge-level:
    backgroundColor: "{colors.brand-yellow}"
    textColor: "{colors.primary}"
    typography: "{typography.caption-bold}"
    rounded: "{rounded.sm}"
    padding: "2px 6px"
  promo-banner:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.on-primary}"
    typography: "{typography.body-sm-medium}"
    padding: "{spacing.sm} {spacing.md}"
  comparison-table:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    typography: "{typography.body-sm}"
    rounded: "{rounded.md}"
    border: "1px solid {colors.hairline}"
  comparison-row:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    padding: "{spacing.md} {spacing.lg}"
    border: "0 0 1px {colors.hairline-soft} solid"
  book-card:
    backgroundColor: "{colors.canvas}"
    rounded: "{rounded.xl}"
    padding: "{spacing.md}"
    border: "1px solid {colors.hairline}"
  product-mockup:
    backgroundColor: "{colors.canvas}"
    rounded: "{rounded.xl}"
    padding: "0"
    border: "1px solid {colors.hairline-soft}"
    shadow: "rgba(5, 0, 56, 0.08) 0px 12px 32px -4px"
  faq-accordion-item:
    backgroundColor: "{colors.canvas}"
    rounded: "{rounded.md}"
    padding: "{spacing.xl}"
    border: "0 0 1px {colors.hairline} solid"
  logo-wall-item:
    backgroundColor: "transparent"
    textColor: "{colors.steel}"
    typography: "{typography.body-md-medium}"
    padding: "{spacing.lg}"
  hero-band:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    typography: "{typography.hero-display}"
    rounded: "0"
    padding: "{spacing.hero}"
  cta-banner-dark:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.on-primary}"
    rounded: "{rounded.feature}"
    padding: "{spacing.section}"
  category-tile:
    backgroundColor: "{colors.canvas}"
    rounded: "{rounded.xl}"
    padding: "{spacing.xl}"
    border: "1px solid {colors.hairline-soft}"
  monster-card:
    backgroundColor: "{colors.canvas}"
    rounded: "{rounded.xxxl}"
    padding: "{spacing.xl}"
    border: "1px solid {colors.hairline-soft}"
  monster-card-locked:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.muted}"
    rounded: "{rounded.xxxl}"
    padding: "{spacing.xl}"
    border: "1px dashed {colors.hairline-strong}"
  radar-chart:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    rounded: "{rounded.lg}"
    padding: "{spacing.lg}"
    border: "1px solid {colors.hairline-soft}"
  podium-place:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.ink}"
    typography: "{typography.stat-display}"
    rounded: "{rounded.xxl}"
    padding: "{spacing.lg}"
    border: "1px solid {colors.hairline-soft}"
  progress-bar:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.brand-yellow}"
    rounded: "{rounded.full}"
    height: 12px
  state-banner:
    backgroundColor: "{colors.surface-yellow}"
    textColor: "{colors.yellow-dark}"
    typography: "{typography.body-sm-medium}"
    rounded: "{rounded.md}"
    padding: "{spacing.sm} {spacing.md}"
    border: "1px solid {colors.hairline}"
  teacher-sidebar:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    typography: "{typography.body-sm-medium}"
    rounded: "0"
    padding: "{spacing.xl} {spacing.md}"
    border: "0 1px 0 0 {colors.hairline} solid"
  footer-region:
    backgroundColor: "{colors.footer-bg}"
    textColor: "{colors.on-dark}"
    typography: "{typography.body-sm}"
    padding: "{spacing.section} {spacing.xxl}"
  footer-link:
    backgroundColor: "transparent"
    textColor: "{colors.on-dark-muted}"
    typography: "{typography.body-sm}"
    padding: "{spacing.xxs} 0"
---

## Overview

「책갈피」는 자신감 있고 다정한 브랜드 보이스로 자신을 드러낸다. 학생 홈은 흰 캔버스를 배경으로, 좌상단의 작은 카나리아 옐로 워드마크와 블루 필 프라이머리 CTA(예: "독후감 쓰기"), 연파랑 필 세컨더리("책 찾기")가 열고, 그 아래로 반려 몬스터·성장 카드·5축 방사형 같은 실제 제품 화면 목업이 시각적 무게를 담당한다. 더 깊은 화면(게이미피케이션·상점·랭킹)에서는 시스템이 활짝 열린다 — 파스텔 피처 카드(로즈·틸·코랄·옐로)가 반려 몬스터 도감의 **6속성 색**을 반영하고, 우수작·성장 스토리 카드가 같은 틴트로 각 장면을 구분한다.

Pretendard가 80px 히어로 디스플레이부터 11px 마이크로 라벨까지 모든 타이포 표면을 지탱한다. Pretendard의 균형 잡힌 한글 자소와 넓은 웨이트 폭은 다정한 제품 사진·친근한 포지셔닝과 자연스럽게 어울린다. 블루 필 프라이머리 버튼(`{rounded.full}`)이 마케팅·학생 CTA를 지배하고, 시그니처 카나리아 옐로({colors.brand-yellow})는 **워드마크·상단 프로모 배너·"옐로 태그" 피처 칩·레벨/포인트 강조**에만 쓰며 프라이머리 CTA로는 쓰지 않는다. 학생 화면이 파스텔로 밝게 열리는 동안, 담임·교무·사서·총괄 콘솔은 흰 카드와 옅은 헤어라인으로 차분하게 정돈된다.

**핵심 특징:**
- 흰 캔버스 + 카나리아 옐로({colors.brand-yellow}) 워드마크 = 알아보기 쉬운 오프닝 시그니처 — 전역 상단에는 브랜드 옐로 헤더 밴드가 놓여 흰 바디와 또렷이 구분되는 것이 이 오프닝의 시그니처다
- 블루 필 프라이머리 CTA({colors.brand-blue} + `{rounded.full}`)가 지배적 인터랙션 요소 — 블랙 필·흰 아웃라인뿐이던 흑백 버튼 위계는 밋밋하다는 피드백으로 2026-09-04 에 블루 한 가족(블루 필·연파랑 필)으로 바꿨다
- 반려 몬스터 도감 **6속성 색**을 반영한 파스텔 피처 카드(옐로·로즈·코랄·틸·민트)
- 모든 UI 표면에 Pretendard(한글 self-host) — 기하학적이고 살짝 둥근 성격
- 실제 제품 화면(몬스터·성장 카드·방사형) 목업을 피처 일러스트로 사용
- 학생=파스텔 탭형 / 교사·관리자=차분한 사이드바 콘솔의 이중 톤
- 대형 다크 푸터({colors.footer-bg}) + 다열 링크

## Colors

> 이 팔레트는 원본 분석의 토큰 값을 그대로 유지하고(색상은 손대지 않음), 명칭·용도만 「책갈피」 맥락으로 다듬었다. `surface-pricing-featured` → `surface-featured`처럼 제품 중립적으로만 개칭.

### 6속성 틴트 매핑 (반려 몬스터 도감)
파스텔 피처 색은 게이미피케이션의 **6속성**(monsters.md §2)과 느슨히 연동한다. 정확한 1:1 고정색은 도감 시드에서 확정하되, 화면 틴트는 아래 대응을 기본 신호로 쓴다.

| 속성(element) | 톤 | 기본 틴트 토큰 |
|------|------|------|
| story(이야기·보라) | 라벤더 | `{colors.surface-featured}` |
| knowledge(지식·파랑) | 블루 | `{colors.brand-blue}` 계열 옅은 배경 |
| emotion(감성·분홍) | 로즈 | `{colors.rose-light}` |
| adventure(모험·주황) | 오렌지 | `{colors.brand-orange-light}` |
| nature(자연·초록) | 틸 | `{colors.teal-light}` |
| imagination(상상·금) | 옐로 | `{colors.yellow-light}` |

### Brand & Accent
- **책갈피 옐로** ({colors.brand-yellow}): 시그니처 카나리아 옐로 — 워드마크·상단 프로모 배너·"옐로 태그" 칩·레벨/포인트 강조
- **Yellow Deep** ({colors.brand-yellow-deep}): 강조·프레스 상태의 진한 변형
- **Yellow Light** ({colors.yellow-light}): 태그 칩·상상 속성 틴트용 옅은 옐로 배경
- **Yellow Dark** ({colors.yellow-dark}): 옐로 태그 전경 텍스트(다크 올리브)
- **Brand Blue** ({colors.brand-blue}): 인라인 링크·강조 카드 보더·지식 속성 액션색
- **Blue Pressed** ({colors.blue-pressed}): 링크·프라이머리 버튼 프레스 상태, 연파랑 필 위 전경
- **Blue Soft / Blue Soft Deep / Blue Soft Pressed** ({colors.blue-soft} · {colors.blue-soft-deep} · {colors.blue-soft-pressed}): 세컨더리·아이콘 버튼의 연파랑 필 배경(기본·호버·프레스)
- **Brand Coral / Coral Light / Coral Dark** ({colors.brand-coral} · {colors.coral-light} · {colors.coral-dark}): 따뜻한 콜아웃·피처 카드 배경·태그 전경(딥 와인)
- **Brand Rose / Rose Light** ({colors.brand-rose} · {colors.rose-light}): 감성 속성 피처 카드 배경
- **Brand Teal / Teal Light / Moss Dark** ({colors.brand-teal} · {colors.teal-light} · {colors.moss-dark}): 자연 속성 카드 배경·딥 그린 텍스트
- **Brand Orange Light** ({colors.brand-orange-light}): 모험 속성 카드 배경

### Surface
- **Canvas White** ({colors.canvas}): 페이지·기본 카드 표면
- **Surface / Surface Soft** ({colors.surface} · {colors.surface-soft}): 섹션 배경, 검색 필 기본, 교사 사이드바
- **Surface Yellow** ({colors.surface-yellow}): 태그 칩·상태 배너용 옐로 틴트 표면
- **Surface Featured** ({colors.surface-featured}): 강조 플랜/카드용 옅은 라벤더
- **Hairline / Hairline Soft / Hairline Strong** ({colors.hairline} · {colors.hairline-soft} · {colors.hairline-strong}): 1px 보더·행 구분·입력 보더

### Text
- **Ink Deep** ({colors.ink-deep}): 밝은 피처 카드 위 헤드라인
- **Ink** ({colors.ink}): 기본 헤드라인·본문
- **Charcoal / Slate / Steel / Stone / Muted**: 본문 강조 → 보조 → 3차 텍스트 → 캡션 → 비활성 순의 계조
- **On Dark / On Dark Muted** ({colors.on-dark} · {colors.on-dark-muted}): 다크 표면 위 흰 텍스트·감광 흰색

### Semantic
- **Success Accent** ({colors.success-accent}): 성공/승인 그린(교사 승인·뱃지 획득 등)
- **Brand Red / Brand Red Dark** ({colors.brand-red} · {colors.brand-red-dark}): 오류 배경·보더
- **Danger** ({colors.danger}): 파괴적 행동 버튼 배경(삭제 등 되돌릴 수 없는 액션)
- **Error Text** ({colors.error-text}): 폼 오류 텍스트
- **Success Surface** ({colors.success-surface}): 성공 상태 배너 배경
- **Success Ink** ({colors.success-ink}): 성공 상태 배너 텍스트(딥 그린)

## Typography

### Font Family
**Pretendard** (primary, self-host): 「책갈피」의 한국어 기본 서체. 80px 히어로부터 11px 마이크로까지 모든 UI 표면에 적용한다. 한글·라틴·숫자의 균형이 좋고 웨이트 폭(100–900)이 넓어 아동친화 톤과 콘솔의 정돈된 톤을 한 서체로 소화한다. RAILS_PLAN §11에 따라 **CDN 대신 self-host**(예: `app/assets/fonts/pretendard`)로 서빙한다.

폰트 스택:
```
Pretendard, "Pretendard Variable", -apple-system, BlinkMacSystemFont,
system-ui, "Apple SD Gothic Neo", "Malgun Gothic", "Noto Sans KR", sans-serif
```

> **원본과의 차이(폰트 교체에 따른 다듬기)**: (1) 서체 Roobert PRO → Pretendard. (2) 한글 가독을 위해 대형 디스플레이의 음수 자간을 완화(hero -2px→-1.5px, display -1.5px→-1px, h1 -1px→-0.5px, stat -1.5px→-1px) — 한글 글자폭은 라틴보다 넓어 과한 음수 트래킹이 판독을 해친다. (3) 본문 계열 행간을 1.5→1.6으로 소폭 상향(독후감 등 긴 한글 본문 가독). (4) 헤딩 웨이트를 500→600으로 통일 — Pretendard 500은 라틴 미디엄 대비 한글에서 약해 보여, 헤드라인 대비를 위해 SemiBold를 헤딩 기본으로 둔다. 크기·라운드·색·스페이싱 등 나머지 토큰은 원본 유지.

### Hierarchy

| Token | Size | Weight | Line Height | Letter Spacing | Use |
|---|---|---|---|---|---|
| `{typography.hero-display}` | 80px | 600 | 1.10 | -1.5px | 마케팅 히어로 헤드라인 |
| `{typography.display-lg}` | 60px | 600 | 1.14 | -1px | 대형 섹션 오프너 |
| `{typography.heading-1}` | 48px | 600 | 1.20 | -0.5px | 페이지 레벨 헤드라인 |
| `{typography.heading-2}` | 36px | 600 | 1.25 | -0.25px | 서브섹션 헤드라인 |
| `{typography.heading-3}` | 28px | 600 | 1.30 | 0 | 카드 타이틀 |
| `{typography.heading-4}` | 22px | 600 | 1.35 | 0 | 피처 타일 타이틀 |
| `{typography.heading-5}` | 18px | 600 | 1.45 | 0 | FAQ 질문·소형 카드 |
| `{typography.subtitle}` | 18px | 400 | 1.60 | 0 | 히어로 서브타이틀 |
| `{typography.body-md}` | 16px | 400 | 1.60 | 0 | 기본 본문 |
| `{typography.body-md-medium}` | 16px | 500 | 1.60 | 0 | 로고월 라벨·본문 강조 |
| `{typography.body-sm}` | 14px | 400 | 1.60 | 0 | 보조 본문·표 셀 |
| `{typography.body-sm-medium}` | 14px | 500 | 1.55 | 0 | 필터·버튼·탭 라벨 |
| `{typography.caption}` | 13px | 400 | 1.45 | 0 | 헬퍼 텍스트 |
| `{typography.caption-bold}` | 13px | 600 | 1.45 | 0 | 뱃지·태그 칩 라벨 |
| `{typography.micro}` | 12px | 500 | 1.40 | 0 | 푸터 마이크로카피 |
| `{typography.micro-uppercase}` | 11px | 600 | 1.40 | 0.5px | 표 섹션 구분(라틴 대문자) |
| `{typography.button-md}` | 15px | 600 | 1.30 | 0 | 필 버튼 라벨 |
| `{typography.stat-display}` | 64px | 700 | 1.10 | -1px | "100만+" 스탯 콜아웃·포디움 |

### Principles
- **한글 가독 우선** — 본문(subtitle/body-*)은 행간 1.55–1.60으로 긴 한글 문장의 판독을 확보한다.
- **본문 최소 14px** — 한글 러닝 텍스트는 `{typography.body-sm}`(14px) 이하로 내리지 않는다. 13px 이하(caption/micro/micro-uppercase)는 **비핵심 라벨·라틴 대문자 마이크로카피** 전용.
- **완화된 음수 자간** — 대형 디스플레이만 -1.5px~-0.5px, 헤딩3 이하는 0. 한글은 라틴식 강한 음수 트래킹을 피한다.
- **웨이트 스케일** — 400(본문) / 500(본문 강조) / 600(헤딩·뱃지·버튼) / 700(스탯). Pretendard는 100–900을 제공하므로, 아동 대상 강한 강조가 필요하면 700을 예외적으로 허용한다.

## Layout

### Spacing System
- **기준 단위**: 4px(주 증분 8px)
- **토큰**: `{spacing.xxs}`(4px) · `{spacing.xs}`(8px) · `{spacing.sm}`(12px) · `{spacing.md}`(16px) · `{spacing.lg}`(20px) · `{spacing.xl}`(24px) · `{spacing.xxl}`(32px) · `{spacing.xxxl}`(40px) · `{spacing.section-sm}`(48px) · `{spacing.section}`(64px) · `{spacing.section-lg}`(96px) · `{spacing.hero}`(120px)
- **섹션 리듬**: 마케팅/학생 홈 `{spacing.section-lg}`(96px); 기능 비교·표는 `{spacing.section}`(64px)로 조임; 스토리 스택은 `{spacing.xxl}`(32px)
- **카드 내부 패딩**: 컴팩트 카드 `{spacing.xl}`(24px); 피처 패널 `{spacing.xxl}`(32px)

### Grid & Container
- 마케팅/콘텐츠 페이지 최대폭 1536px, 거터 32px(구현 셸 상한과 일치 — 아래 "공통 컴포넌트 클래스 › 페이지 셸")
- 랭킹 포디움은 3열(Top3), 몬스터 도감은 반응형 그리드(모바일 2열 → 데스크톱 4~6열)
- 우수작·토론 목록은 필터 드롭다운을 둔 2열 그리드
- 교사 콘솔은 좌측 사이드바 + 우측 콘텐츠 2분할

### Whitespace Philosophy
학생·마케팅 표면은 넉넉한 여백(`{spacing.hero}` 120px 히어로 패딩)으로 작은 워드마크에 숨 쉴 공간을 준다. 교사 검토 목록·비교표 등 밀도가 필요한 화면은 리듬을 크게 조인다.

## Elevation & Depth

전체적으로 플랫하게 가되, 제품 목업에만 전략적으로 깊이를 준다.

| Level | Treatment | Use |
|---|---|---|
| 0 (flat) | 그림자 없음; `{colors.hairline-soft}` 보더 | 기본 카드·표 행·폼 입력 |
| 1 (subtle) | `rgba(5, 0, 56, 0.04) 0px 1px 2px 0px` | 살짝 떠 있는 타일 |
| 2 (card) | `rgba(5, 0, 56, 0.06) 0px 4px 12px 0px` | 표준 피처 카드 |
| 3 (mockup) | `rgba(5, 0, 56, 0.08) 0px 12px 32px -4px` | 히어로 제품 목업 프레이밍 |
| 4 (modal) | `rgba(5, 0, 56, 0.12) 0px 16px 48px -8px` | 모달·드롭다운·진화 연출 오버레이 |

### Decorative Depth
- 히어로의 분위기 깊이는 실제 제품 화면 목업(반려 몬스터·성장 카드·방사형)이 담당한다 — 요소를 z-오프셋으로 겹치고 색블록 틴트를 뒤에 깐다.
- 파스텔 피처 카드는 채도 있는 배경색 자체로 시각적 무게를 갖는다(그림자 최소화).
- 진화·신규 발견 연출은 Level 4 오버레이 + 짧은 모션으로 처리한다.

## Shapes

### Border Radius Scale

| Token | Value | Use |
|---|---|---|
| `{rounded.xs}` | 4px | 소형 칩·마이크로 컨트롤 |
| `{rounded.sm}` | 6px | 레벨/할인 뱃지 |
| `{rounded.md}` | 8px | 입력·검색 필 |
| `{rounded.lg}` | 12px | 표준 카드·표 컨테이너·방사형 프레임 |
| `{rounded.xl}` | 16px | 플랜·피처 패널·책 카드 |
| `{rounded.xxl}` | 20px | 대형 피처·포디움 자리 |
| `{rounded.xxxl}` | 28px | 파스텔 피처 카드·몬스터 카드 |
| `{rounded.feature}` | 32px | 히어로/하단 CTA 배너 |
| `{rounded.full}` | 9999px | 모든 버튼·필 탭·뱃지·진행 바 |

### Illustration Geometry
- 제품 화면 목업은 `{rounded.xl}`(16px) + 옅은 드롭 섀도로 렌더
- 우수작·성장 스토리 카드는 `{rounded.xxxl}`(28px) 풀블리드
- 책 카드 썸네일은 `{rounded.xl}`(16px)
- 몬스터 이미지는 애니메이션 WebP를 몬스터 카드(28px) 중앙에 배치, 잠금 상태는 점선 보더

## Components

> no-hover 정책에 따라 hover 상태는 문서화하지 않는다. 기본·프레스/활성 상태만 기술.

### Buttons

**`button-primary`** — 블루 필 프라이머리 CTA, 지배적 액션("독후감 쓰기", "저장", "학생 추가"). 2026-09-04 이전에는 블랙 필(`{colors.primary}`)이었다.
- 배경 `{colors.brand-blue}`, 텍스트 `{colors.on-primary}`, 타이포 `{typography.button-md}`, 패딩 `12px 24px`, 라운드 `{rounded.full}`.
- 프레스 `button-primary-pressed`는 `{colors.blue-pressed}`로, 비활성 `button-primary-disabled`는 `{colors.hairline}` 배경 + `{colors.muted}` 텍스트.

**`button-yellow`** — 브랜드 강조 순간용 옐로 필. 배경 `{colors.brand-yellow}`, 텍스트 `{colors.primary}`.

**`button-blue`** — 인라인 액션 콜아웃용 블루 필. 배경 `{colors.brand-blue}`, 텍스트 `{colors.on-primary}`. 프라이머리가 블루로 바뀐 뒤로는 `button-primary`와 같은 모습이며 기존 마크업 호환용으로 남긴다.

**`button-secondary`** — 세컨더리 연파랑 필("책 찾기", "취소", 목록 행의 보기·편집). 배경 `{colors.blue-soft}`, 텍스트 `{colors.blue-pressed}`, 보더 없음. 프레스 `button-secondary-pressed`는 `{colors.blue-soft-pressed}`. 2026-09-04 이전에는 흰 아웃라인 필이었다.

**`button-on-dark`** — 다크 CTA 배너용 화이트 필. 배경 `{colors.on-dark}`, 텍스트 `{colors.primary}`.

**`button-ghost`** — 조용한 사각 고스트 버튼. 배경 투명, 텍스트 `{colors.ink}`, 라운드 `{rounded.md}`, 패딩 `8px 12px`.

**`button-link`** — 인라인 텍스트 링크. 텍스트 `{colors.brand-blue}`, 타이포 `{typography.body-sm-medium}`.

**`button-icon-circular`** — 40×40px 원형 유틸 버튼(아동 터치 타깃 상향). 배경 `{colors.blue-soft}`, 전경 `{colors.blue-pressed}`, 보더 없음, 라운드 `{rounded.full}`.

### Cards & Containers

**`card-base`** — 표준 콘텐츠 카드. 배경 `{colors.canvas}`, 라운드 `{rounded.xl}`, 패딩 `{spacing.xl}`, 보더 `1px solid {colors.hairline-soft}`.

**`card-feature`** — 32px 코너의 화이트 피처 카드. 라운드 `{rounded.feature}`, 패딩 `{spacing.xxl}`.

**`card-feature-yellow / -coral / -teal / -rose`** — 6속성 파스텔 피처 카드. 각 배경 `{colors.brand-yellow}` / `{colors.coral-light}` / `{colors.teal-light}` / `{colors.rose-light}`, 텍스트 `{colors.primary}`, 라운드 `{rounded.xxxl}`, 패딩 `{spacing.xxl}`.

**`card-story`** — 우수작·성장 스토리 카드. 배경 `{colors.canvas}`, 라운드 `{rounded.xxxl}`, 패딩 `0`(이미지 풀필), 보더 `1px solid {colors.hairline-soft}`.

**`card-stat`** — "100만+ 권 읽음" 같은 스탯 셀. 타이포 `{typography.stat-display}`, 패딩 `{spacing.lg}`.

**`plan-card` / `plan-card-featured` / `plan-card-dark`** — 기능·플랜 비교 카드 3종(비교표·상점 요금 비교 등 강조 레이아웃). 표준=흰 카드+헤어라인, featured=`{colors.surface-featured}`+블루 2px 보더, dark=`{colors.primary}` 다크 카드.

### Inputs & Forms

**`text-input`** / **`text-input-focused`** — 표준 텍스트 필드(높이 44px, 보더 `1px solid {colors.hairline-strong}`), 활성 시 `2px solid {colors.brand-blue}`.

**`search-pill`** — 검색 바. 배경 `{colors.surface}`, 라운드 `{rounded.md}`, 높이 44px.

**`filter-dropdown`** — 필 형 필터("학년"/"장르"/"카테고리"). 배경 `{colors.canvas}`, 라운드 `{rounded.full}`, 보더 `1px solid {colors.hairline-strong}`.

### Tabs

**`pill-tab`** + **`pill-tab-active`** — 필 탭 내비. 비활성=흰 배경+`{colors.steel}` 텍스트, 활성=`{colors.brand-blue}` 배경+흰 텍스트.

**`toggle-two-state`** — 2상태 필 토글(예: 주간/월간, 학급/전교). 배경 `{colors.surface}`, 라운드 `{rounded.full}`, 패딩 `4px`.

### Badges & Status

**`badge-promo`** — 옐로 프로모 배지. 배경 `{colors.brand-yellow}`, 타이포 `{typography.caption-bold}`.

**`badge-tag-yellow` / `-lavender` / `-coral`** — 소프트 피처 태그 칩(속성·장르 라벨). 각각 옐로/라벤더/코랄 배경 + 대응 다크 전경.

**`badge-success`** — 그린 성공 인디케이터(교사 승인·뱃지 획득). 배경 `{colors.success-accent}`, 텍스트 흰색.

**`badge-level`** — 레벨/포인트 사각 배지("Lv.3", "+30P"). 배경 `{colors.brand-yellow}`, 텍스트 `{colors.primary}`, 라운드 `{rounded.sm}`.

**`promo-banner`** — 상단 내비 위 블랙 프로모 스트립. 배경 `{colors.primary}`, 텍스트 `{colors.on-primary}`. 인라인 옐로 필 강조 가능. 시즌/프로모 배너는 옐로 헤더 밴드와의 옐로-온-옐로 적층을 피해 항상 블랙 프로모 스트립(`{colors.primary}`/`{colors.on-primary}`)으로 렌더한다.

### Tables

**`comparison-table`** / **`comparison-row`** — 기능/루브릭 비교표. 흰 배경, 타이포 `{typography.body-sm}`, 행 하단 보더 `1px solid {colors.hairline-soft}`, 행 패딩 `{spacing.md} {spacing.lg}`.

### 책갈피 Signature Components

RAILS_PLAN §12가 요구하는 「책갈피」 고유 표면을 동일 토큰 언어로 정의한다.

**`product-mockup`** — 독후감 에디터·도감·성장 카드 등 실제 제품 화면을 피처 일러스트로 렌더. 라운드 `{rounded.xl}`, 보더 `1px solid {colors.hairline-soft}`, 섀도 Level 3.

**`monster-card`** / **`monster-card-locked`** — 반려 몬스터 카드(발견=흰 카드+속성 틴트 악센트, 미발견=`{colors.surface}` 점선 보더 실루엣). 라운드 `{rounded.xxxl}`, 패딩 `{spacing.xl}`. **몬스터 도감 그리드**는 이 카드를 반응형 그리드(모바일 2 → 데스크톱 4~6열)로 배열하고, 완성도 표시는 `progress-bar`.

**`radar-chart`** — 5축 방사형(내용·감상·삶·구성·맞춤법) 인라인 SVG를 감싸는 프레임. 라운드 `{rounded.lg}`, 패딩 `{spacing.lg}`. 축 라벨은 `{typography.caption}`, 값 강조는 `{colors.brand-blue}`.

**`podium-place`** — 랭킹 Top3 포디움 자리. 타이포 `{typography.stat-display}`, 라운드 `{rounded.xxl}`. 1위는 `{colors.brand-yellow}` 악센트, 성장 신호(도감 완성도·진화 단계)를 시각 배지로 노출.

**`progress-bar`** — 레벨·도감·진화 진행 바. 트랙 `{colors.surface}`, 필 `{colors.brand-yellow}`, 라운드 `{rounded.full}`, 높이 12px.

**`state-banner`** — 상태/빈/에러 배너. 로딩("AI 첨삭 중")·빈 상태·폴백 안내는 `{colors.surface-yellow}` + `{colors.yellow-dark}`, 오류는 `{colors.brand-red}` + `{colors.brand-red-dark}` 보더로 변주.

**진화 로드맵 / 케어 상점** — 진화 로드맵은 `card-feature`를 단계별(기본형→성장형→완전형)로 연결하고 각 노드에 `badge-level`(조건)과 `progress-bar`를 얹는다. 케어/진화 아이템 상점은 `book-card`와 동형의 아이템 카드 그리드 + `button-yellow` 구매 CTA + `badge-level` 가격(포인트)으로 구성한다.

### Documentation Components

**`book-card`** — 책 썸네일 카드. 배경 `{colors.canvas}`, 라운드 `{rounded.xl}`, 패딩 `{spacing.md}`, 보더 `1px solid {colors.hairline}`.

**`category-tile`** — 장르·카테고리 타일. 라운드 `{rounded.xl}`, 패딩 `{spacing.xl}`, 보더 `1px solid {colors.hairline-soft}`.

**`faq-accordion-item`** — FAQ/도움말 패널. 라운드 `{rounded.md}`, 패딩 `{spacing.xl}`, 하단 보더 `1px solid {colors.hairline}`.

**`logo-wall-item`** — 참여 학교/파트너 워드마크 셀. 배경 투명, 텍스트 `{colors.steel}`, 타이포 `{typography.body-md-medium}`.

### Navigation

**Top Navigation** — 브랜드 옐로 스티키 밴드(배경 `{colors.brand-yellow}`, 하단 경계 `{colors.brand-yellow-deep}` 1px). 좌측에 앱 아이콘 로고 + 다크 잉크 워드마크(`{colors.ink}`), 학생은 우측에 계정 컨트롤(이름 "○○님"·마이페이지·로그아웃, 옐로 위 흰 필 + 헤어라인 + 옅은 그림자)을 싣는다(구 학생 서브헤더 통합). 교직원·총괄은 워드마크만. 전 역할 공통 적용, 흰 바디와 또렷이 구분. 높이 ~56px(모바일 48px).

**`app-header`** — 전역 브랜드 헤더 밴드. 배경 `{colors.brand-yellow}`, 하단 보더 `{colors.brand-yellow-deep}`, `sticky`(top:0, z-index 30), 내부 컨텐츠는 `{shell-max-wide}` 중앙정렬 + `<main>`과 동일 유틸 거터.

**`app-wordmark`** — 헤더 밴드 좌측 책갈피 워드마크. 앱 아이콘(`/icon.png`, 32px rounded) + 텍스트 `{colors.ink}` 700 웨이트, `root` 링크. 옐로 위 대비 ≈ 10.5:1.

**`teacher-sidebar`** — 담임 콘솔 좌측 사이드바(그룹형 메뉴). 배경 `{colors.surface}`, 타이포 `{typography.body-sm-medium}`, 우측 보더 `1px solid {colors.hairline}`. 검토 목록·학생 관리·미션/퀴즈·루브릭·리포트 그룹.

### Signature Layout

**`hero-band`** — 마케팅/학생 홈 히어로. 배경 `{colors.canvas}`, 패딩 `{spacing.hero}`. 중앙 정렬 헤드라인(`{typography.hero-display}`) + 서브타이틀 + 버튼 행 + 하단 제품 목업.

**`cta-banner-dark`** — 피처 페이지 하단 다크 CTA 배너. 배경 `{colors.primary}`, 라운드 `{rounded.feature}`, 패딩 `{spacing.section}`. 중앙 헤드라인 + `button-on-dark`.

**`footer-region`** / **`footer-link`** — 대형 다열 다크 푸터. 배경 `{colors.footer-bg}`, 패딩 `{spacing.section} {spacing.xxl}`. 섹션 헤딩 `{typography.body-md-medium}` `{colors.on-dark}`, 링크 `{colors.on-dark-muted}`.

## Do's and Don'ts

### Do
- `{colors.brand-yellow}`는 워드마크·상단 프로모 배너·"옐로 태그" 칩·레벨/포인트 강조에만
- `{colors.brand-blue}`(블루 필)를 모든 표면의 지배적 CTA로 — 블랙 `{colors.primary}`는 텍스트·다크 배너·푸터에만
- 파스텔 피처 카드(옐로·로즈·코랄·틸)를 흰 피처 카드와 같은 뷰포트에서 짝지어 6속성 리듬을 만들기
- 모든 버튼·필 탭·상태 배지·진행 바에 `{rounded.full}`
- 파스텔 피처·몬스터 카드에 `{rounded.xxxl}`(28px)
- 실제 제품 화면(몬스터·성장 카드·방사형)을 피처 일러스트로
- 모든 UI 표면에 Pretendard 유지, 한글 본문 최소 14px
- 전역 헤더 밴드는 `{colors.brand-yellow}` 배경 + 다크 워드마크로 흰 바디와 구분(옐로=악센트 원칙은 본문에서 유지)

### Don't
- 표준 CTA나 큰 배경 면에 `{colors.brand-yellow}` 쓰지 않기(단, 전역 헤더 밴드는 예외 — 브랜드 아이덴티티로 허용. 그 외 본문 큰 면은 금지 유지)
- 옐로 + 6속성 파스텔 외 임의 악센트색 추가하지 않기
- 버튼 코너를 각지게 만들지 않기(필은 브랜드 시그니처)
- 히어로 행간을 1.10 아래로 낮추지 않기
- 플랫 문서 카드에 무거운 그림자 남발 금지(엘리베이션은 제품 목업에만)
- 한글 러닝 텍스트를 13px 이하로 내리지 않기, 라틴식 강한 음수 자간 지양

## Responsive Behavior

### Breakpoints
| Name | Width | Key Changes |
|---|---|---|
| Mobile (small) | < 480px | 1열. 히어로 36px. 필 내비 → 햄버거. 카드 1-up. |
| Mobile (large) | 480 – 767px | 피처 타일 2-up. 히어로 48px. 몬스터 도감 2열. |
| Tablet | 768 – 1023px | 2열 피처 그리드. 필 탭 내비 복귀. 교사 사이드바 접힘. |
| Desktop | 1024 – 1279px | 포디움 3열. 도감 4열. 히어로 64px. 교사 2분할. |
| Wide Desktop | ≥ 1280px | 풀 히어로, 80px 디스플레이. 도감 6열. |

### Touch Targets
- 필 버튼 40–44px 유효 높이(아동 대상 상향)
- 원형 아이콘 버튼 40×40px 데스크톱 → 44×44px 모바일
- 폼 입력·검색 필 44px 높이
- 필터 드롭다운 ~36px → 모바일 44px

### Collapsing Strategy
- **프로모 배너**: 풀폭 유지, < 480px에서 말줄임
- **상단 내비**: 1024px 미만 햄버거
- **히어로**: 2열 → < 1024px 스택
- **몬스터 도감 그리드**: 6열 → 4열 → 2열, 상세는 시트/모달
- **비교표**: 4열 → 2열 태블릿 → 1열 모바일, 표는 가로 스크롤
- **히어로 타이포**: 80 → 60 → 48 → 36px
- **푸터**: 6열 → 3열 → 2열 → 소형 모바일 아코디언

### Image Behavior
- 제품 목업은 종횡비 유지, 폴드 아래 lazy-load
- 스토리 사진은 16:9 풀블리드
- 몬스터 애니메이션 WebP는 카드 중앙, 잠금 상태 실루엣

## Iteration Guide

1. 한 번에 하나의 컴포넌트에 집중
2. 컴포넌트명·토큰을 직접 참조
3. 편집 후 `npx @google/design.md lint DESIGN.md` 실행
4. 새 변형은 별도 `components:` 항목으로 추가
5. 본문은 `{typography.body-md}`, 강조는 `{typography.subtitle}` 기본
6. `{colors.brand-yellow}`는 워드마크·프로모 배너·옐로 태그·레벨/포인트로 한정
7. 필 버튼(`{rounded.full}`) 항상
8. 제품을 보여줄 땐 실제 「책갈피」 화면(몬스터·성장 카드·방사형) 목업 사용
9. 타이포는 Pretendard 유지, 한글 본문 최소 14px·행간 1.55+

## Known Gaps

- 다크 모드 토큰 값 미확정(교사 콘솔·야간 사용 대비 후속)
- 애니메이션/트랜지션 타이밍 미추출(진화 연출·Turbo Stream 갱신은 150–250ms ease 권장)
- Pretendard Variable 축(웨이트) 세부 매핑은 self-host 에셋 확정 시 고정
- 6속성 정확 고정색은 monsters.md 도감 시드에서 최종 확정(본 문서는 틴트 대응만 규정)
- 원본(Miro)에서 상속된 마케팅 전용 컴포넌트(app-store/capterra 배지)는 교내 앱에 부적합하여 제외함

## Implementation (Rails · Tailwind v4 매핑)

> 이 절은 위 토큰·컴포넌트 원칙이 실제 코드에 어떻게 연결됐는지 기록한다(2026-07 디자인 개편: Phase 1·2 + Phase 3 대표 화면).

### 토큰 & 폰트
- **색·폰트 토큰** → `app/assets/tailwind/application.css`의 `@theme`에 DESIGN.md 값과 1:1 매핑(`--color-brand-yellow: #ffd02f`, `--color-ink`, `--color-surface`, `--color-hairline`, `--color-brand-blue`, 6속성 파스텔 등). 색만 신규 도입 없이 이식하고, Tailwind 기본 팔레트(gray/amber/rose…)는 유지(기존 뷰 회귀 방지). 생성 유틸 예: `bg-brand-yellow`·`text-ink`·`border-hairline`·`bg-surface-featured`. **rounded/spacing/typography 스케일은 Tailwind 기본 스케일에 의존**(`rounded-xxxl`·`text-hero-display` 같은 DESIGN.md 토큰명 그대로의 유틸은 생성되지 않으며, `.card-feature` 등 일부 컴포넌트 클래스에서만 `--radius-card`/`--radius-feature` 전용 토큰을 별도로 사용한다).
- **Pretendard 자체호스팅**: `app/assets/fonts/pretendard/PretendardVariable.woff2`(가변, 전 웨이트) + `app/assets/stylesheets/application.css`의 `@font-face`. `--font-sans`를 Pretendard 스택으로 덮어 전역 기본 폰트 지정. CSP `font_src :self`(외부 CDN 미사용).
- **전역 base**: 본문 배경(page=`#f7f7f3`) 위에 흰 canvas 카드를 올려 표면을 분리하고, `:focus-visible` 브랜드 블루 링(제거 금지), `::selection`(yellow-light), `@media (prefers-reduced-motion: reduce)`를 적용한다. 관리자 레이아웃은 유틸리티로 중립 surface 배경을 유지한다.

### 공통 컴포넌트 클래스 (`@layer components`)
반복 빈도 높은 패턴만 클래스화(모든 조합 추상화하지 않음). HTML의 Tailwind 유틸이 항상 덮어쓸 수 있음.
- **페이지 셸**: `.page-shell`(width:100%+중앙정렬) + 폭 변형 `.page-shell-wide` / `-content` / `-reading` / `-form`. **상한은 4종 모두 1536px 로, 레이아웃 `<main>`(`max-w-[1536px]`)과 같다** — 좁은 상한(content 1280·form 960·reading 840)이 독후감·도서·폼 화면을 과도하게 조여 좌우 여백만 남기던 문제를 해소한 것(2026-07-28). 변형 클래스는 화면 성격의 의미 표식으로 남겨 두어, 개별 화면만 다시 좁힐 때 `--shell-max-*` 한 곳에서 되돌린다. **가로 거터·세로 리듬은 레이아웃 `<main>`이 소유**(셸에 패딩 없음 — 이중 패딩 방지). 헤더: `.page-header`/`.page-title`/`.page-subtitle`/`.page-actions`(`.page-title`은 좌측 3px `{colors.brand-yellow}` 악센트 바로 강조 지점을 표시).
- **버튼**: `.btn` + `.btn-primary`(검은 필=저장·제출·확정 및 교직원 주요 행동)/`-yellow`(학생 시작·참여)/`-blue`(동기화·검토 등 정보성 도구)/`-secondary`(흰 캔버스 아웃라인=취소·뒤로·보조 탐색)/`-subtle`/`-danger`/`-icon` + 크기 `.btn-sm`/`-lg`/`-block`. 최소 44px 터치이며 hover/active/disabled 상태를 모두 제공한다. 한 행동 묶음의 컬러 필 버튼은 1개를 원칙으로 한다.
- **카드**: `.card`(16px 헤어라인)/`.card-feature`(32px)/`.card-muted`/`.stat-card`(+`__value`/`__label`). 기본 카드에는 따뜻한 페이지 배경에서 흰 표면을 구분하는 2단계 저강도 그림자를 적용하고, 학생 핵심 진입 카드만 yellow/lavender/coral/mint 표면 유틸로 강조한다.
- **폼**: `.form-label`/`.form-input`/`.form-select`/`.form-textarea`/`.form-hint`/`.form-error`(포커스 시 브랜드 블루 보더).
- **배지**: `.badge` + `-neutral`/`-yellow`/`-success`/`-info`/`-warning`/`-danger` + 크기 변형 `.badge-sm`(여백만 좁힌 컴팩트 — 글자는 기본과 같은 13px, 좁은 도서 카드용)/`.badge-lg`(15px, 도서 상세 메타). 초등 전학년 가독성 하한 때문에 배지 글자는 13px 아래로 내리지 않는다.
- **진행바**: `.progress-bar` > `.progress-bar__fill`(brand-yellow). **상태배너/알림**: `.state-banner` + `--success`/`--error`/`--info`(flash·빈/로딩/오류 공용).

### 레이아웃 & 반응형(구현)
- **데스크톱 루트 폰트 확대(2단계)**: `screen` 한정으로 `min-width:1024px`→`106.25%`(17px), `min-width:1280px`→`112.5%`(18px). 모바일/태블릿(<1024px)은 기존 16px 유지. 토큰·유틸이 거의 전부 rem 이라 글자뿐 아니라 간격·아이콘·최소 터치 영역까지 함께 비례 확대되어 넓은 화면이 "PC 확대판"이 된다(초등 전학년 대상 — 본문에 흔한 12~14px 는 데스크톱에서 특히 작다). **2단계인 이유**: 미디어쿼리 길이는 루트 폰트와 무관하게 초기값(16px) 기준이라 1024px 뷰포트는 `lg:` 다단 레이아웃을 쓰면서 실효 공간만 배율만큼 줄어든다 — 그 구간을 17px 로 완만하게 두고 여유가 실제로 있는 xl 부터 18px 로 올린다. **뷰별 반응형 분기(`text-xs sm:text-base`)를 뿌리지 않고 이 한 곳에서만 조절한다.** 인쇄 레이아웃은 영향 없음.
- **셸 상한은 px 고정**: 위 확대에 폭까지 딸려 넓어지면(1536→1728px) 콘텐츠가 좌우로 더 벌어지므로 `--shell-max-*`는 rem 이 아닌 px 로 못박는다. 폭은 그대로, 안쪽 글자·간격만 커진다.
- **`text-xs`(12px)는 메타 전용 — 본문 하한은 `text-sm`(14px)**: 초등 전학년 대상이라 읽어야 하는 텍스트를 12px 로 두지 않는다.
  - `text-sm` 이상: 완결된 안내·설명 문장, 사용자 생성 본문(미션·챌린지 `description`, AI 코멘트), 섹션 헤딩, 조작부 라벨(버튼·링크). 폼의 `.form-hint`/`.form-error`도 "읽어야 하는 문장"이라 같은 하한(14px)을 따른다.
  - `text-xs` 유지: 저자·출판사·날짜·도감 번호·XP/P/Lv·카운트 같은 **메타**, 배지 내부, 진행바 수치, `font-mono` 설정값·코드.
  - 판단 기준은 "학생이 읽고 이해해야 하는 문장인가" — 그렇다면 메타가 아니다.
- `layouts/application`: 고정 `mt-28`·브레이크포인트 컨테이너 제거 → `<main>`이 `max-w-[1536px] mx-auto` + 유동 거터(`px-4 sm:px-6 lg:px-8`) + `py-6`. flash=`shared/_flash`(state-banner 토스트).
- `layouts/admin`: 반응형 오프캔버스 사이드바(lg↑ 고정 / lg↓ 햄버거 패널 = `admin-sidebar` Stimulus, backdrop·Escape), 본문 `max-w-[1536px]`, `overflow-x-hidden` 가로스크롤 가드.
- 학생 내비(`shared/_student_nav`): 반응형 필 탭(데스크톱 줄바꿈/모바일 disclosure), 활성=라벤더 파스텔 필+짙은 브랜드 블루 텍스트+`aria-current="page"`.

### 역할 톤(적용 현황)
학생(대시보드·로그인 선택 카드)=밝은 파스텔 표면+옐로 시작·참여 CTA; 교직원·관리자(admin 콘솔·교직원 로그인)=차분한 흰 카드+헤어라인, 검은 주요 CTA와 필요한 블루 도구 행동. 옐로는 워드마크·레벨/포인트·학생의 긍정적 진입 행동에 한정하고, 최종 저장·제출은 검은 필(`.btn-primary`)로 구분한다.

### 이월(후속 묶음)
게임/도감/상점/미션/랭킹(Phase 4)·커뮤니티(Phase 5)·교사/사서/교무 심화(Phase 6)·관리자 CRUD 전면(Phase 7)·인쇄/메일/PWA/turbo 정리(Phase 8)는 이 공통 시스템을 화면군 단위로 확장 적용.
