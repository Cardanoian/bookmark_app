# app/helpers — 뷰 헬퍼

뷰의 표시 로직을 담는 헬퍼 계층. 주로 도메인 enum/키를 한국어 라벨·Tailwind 색상 클래스로 매핑하거나, WebP/이모지 스프라이트·인라인 SVG 차트처럼 서버 렌더 표현을 만든다. 라벨/색 상수는 각 헬퍼 모듈 상단에 상수 해시로 둔다.

## 파일
- `application_helper.rb` — 전역 헬퍼(현재 비어 있음, 공통 헬퍼 추가용 자리).
- `monsters_helper.rb` — 몬스터 도감 표시. `monster_sprite`(`image_key` WebP 렌더·누락 시 이모지 폴백)·`monster_emoji`(종→대표 이모지)·`element_label`/`element_badge_classes`(속성 라벨·색)·`condition_label`·`condition_progress`(진화 조건 라벨·`ReadingStats` 대비 진행값).
- `reports_helper.rb` — 독후감/첨삭 뱃지. `ai_status_badge`(첨삭 상태 pill)·`level_badge`(A/B/C 등급 배지)·`axis_label`(5축 라벨).
- `shops_helper.rb` — 상점 카테고리 한국어 라벨(`category_label`: 먹이·진화의 돌·케어·장식·액세서리).
- `teacher_helper.rb` — `radar_chart_svg`: 5축 방사형(오각형) 차트를 JS 없이 서버 렌더 인라인 SVG(격자·스포크·데이터 폴리곤·축 라벨)로 반환.

---
> ⚠️ **유지보수 규칙**: 이 폴더의 파일이 추가·삭제되거나 역할이 바뀌면 이 CLAUDE.md도 함께 갱신하세요. 하위 폴더 구조가 바뀌면 관련 상·하위 CLAUDE.md 링크도 확인하세요.
