# app/helpers — 뷰 헬퍼

뷰의 표시 로직을 담는 헬퍼 계층. 주로 도메인 enum/키를 한국어 라벨·Tailwind 색상 클래스로 매핑하거나, WebP/이모지 스프라이트·인라인 SVG 차트처럼 서버 렌더 표현을 만든다. 라벨/색 상수는 각 헬퍼 모듈 상단에 상수 해시로 둔다.

## 파일
- `application_helper.rb` — 전역 헬퍼. `student_back_path`(학생 공통 헤더 뒤로가기 목적지 — referer 히스토리 back 이 아니라 현재 `controller_path#action_name` 기준으로 한 단계 "상위 메뉴" 경로를 계산. 최상위 5메뉴(홈·내 서재·독서활동·도감·랭킹)·미등록 화면은 `root_path`, 자식 화면은 `STUDENT_BACK_PARENTS` 심볼→`public_send`. 상위가 자기 자신이면 `_student_header`가 버튼을 숨김).
- `games_helper.rb` — 게임 종류별 액센트 색 매핑. `game_accent`/`GAME_ACCENTS`(quiz·classic·vocab·whoami·book → 배경·글자색 클래스, 미지정 key 는 quiz 로 폴백).
- `monsters_helper.rb` — 몬스터 도감 표시. `monster_sprite`(`image_key` WebP 렌더·누락 시 이모지 폴백)·`monster_emoji`(종→대표 이모지)·`element_label`/`element_badge_classes`(속성 라벨·색)·`condition_label`·`condition_progress`(진화 조건 라벨·`ReadingStats` 대비 진행값)·**`unlock_condition_label`/`unlock_progress_items`**(잠긴 카드용 해금 조건 문장형 라벨 + `[{label:, current:, target:, met:}]` 진행도 배열, 현재값은 목표치를 넘지 않게 클램프).
- `reports_helper.rb` — 독후감/첨삭 뱃지. `ai_status_badge`(첨삭 상태 pill)·`level_badge`(A/B/C 등급 배지)·`axis_label`(5축 라벨).
- `schools_helper.rb` — `school_region_label`: "서울특별시교육청" → "서울특별시" 처럼 교육청 접미를 떼어 표시(학교 선택 하이브리드 피커의 시도 라벨).
- `teacher_helper.rb` — `radar_chart_svg`: 5축 방사형(오각형) 차트를 JS 없이 서버 렌더 인라인 SVG(격자·스포크·데이터 폴리곤·축 라벨)로 반환.

---
> ⚠️ **유지보수 규칙**: 이 폴더의 파일이 추가·삭제되거나 역할이 바뀌면 이 CLAUDE.md도 함께 갱신하세요. 하위 폴더 구조가 바뀌면 관련 상·하위 CLAUDE.md 링크도 확인하세요.
