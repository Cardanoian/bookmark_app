# app/helpers — 뷰 헬퍼

뷰의 표시 로직을 담는 헬퍼 계층. 주로 도메인 enum/키를 한국어 라벨·Tailwind 색상 클래스로 매핑하거나, WebP/PNG 이미지·SVG 스프라이트·인라인 SVG 차트처럼 서버 렌더 표현을 만든다. 라벨/색 상수는 각 헬퍼 모듈 상단에 상수 해시로 둔다.

## 파일
- `books_helper.rb` — 도서 표시 공통 헬퍼. `book_meta_badges(book, size:, wrapper_class:)`(고전 여부[category enum `classic?`] + 장르[`genre`] 메타 배지를 한 번에 렌더 — 둘 다 없으면 빈 문자열이라 어느 카드에 삽입해도 안전, 크기는 `BADGE_SIZE_CLASSES` 매핑 — `size: :sm`=`badge-sm`[홈 그리드·목록. 글자는 기본 배지와 같은 13px 이고 여백만 컴팩트]·`:md`=기본·`:lg`=`badge-lg` 15px[도서 상세])·`book_genre_label(book)`(공란·`미분류`는 숨김, genre 는 이미 한국어 라벨이라 그대로 표시). 대시보드 그리드·독서활동·내 서재·도서 카드/상세·독후감 파셜 등 책이 노출되는 화면이 공용한다.
- `application_helper.rb` — 전역 이미지 아이콘 시스템. `ui_icon`(공용 `ui-icons.svg` symbol 렌더·장식용 `aria-hidden` 기본), `icon_text`(아이콘+라벨), `sticker_icon`(기존 반응 이모지 데이터를 프로젝트 아이콘으로 표시), `empty_state_image`(빈 화면 종류를 128×128 AI PNG에 매핑) 제공.
- `games_helper.rb` — 게임 종류별 액센트 색 매핑. `game_accent`/`GAME_ACCENTS`(quiz·whoami·book·sequel → 배경·글자색 클래스, 미지정 key 는 quiz 로 폴백; 게임 재구성 Phase 1 에서 classic·vocab 키 제거, Phase 2 에서 sequel 추가).
- `monsters_helper.rb` — 몬스터 도감 표시. `monster_sprite`는 기본으로 `image_key` 정적 PNG를 렌더하며, 상세 상단만 `animated: true`로 애니메이션 WebP를 선택한다(누락 시 공용 미발견 SVG 폴백). 그 외 `element_label`/`element_badge_classes`(속성 라벨·색)·`condition_label`·`condition_progress`(진화 조건 라벨·`ReadingStats` 대비 진행값)·**`unlock_condition_label`/`unlock_progress_items`**(잠긴 카드용 해금 조건 문장형 라벨 + `[{label:, current:, target:, met:}]` 진행도 배열, 현재값은 목표치를 넘지 않게 클램프).
- `reports_helper.rb` — 독후감/첨삭 뱃지. `ai_status_badge`(교사 뷰 첨삭 상태 pill)·`student_status_badge`(학생 뷰 — 확인 완료/다시 시도/**작성 중**/선생님 확인 중/첨삭 준비 중)·`level_badge`(A/B/C 등급 배지)·`axis_label`(5축 라벨). **`student_status_badge` 의 `draft?`(미제출) 분기는 `ai_status == "done"` 판정보다 앞에 둔다** — OCR 초안은 판독을 마치면 done 이라, 제출 여부를 보지 않으면 아직 내지도 않은 글이 "선생님 확인 중"으로 표시되고 학생이 그 말을 믿어 제출하기를 누르지 않는다(첨삭이 영영 안 붙는 원인의 학생 쪽 절반).
- `schools_helper.rb` — `school_region_label`: "서울특별시교육청" → "서울특별시" 처럼 교육청 접미를 떼어 표시(학교 선택 하이브리드 피커의 시도 라벨).
- `teacher_helper.rb` — `radar_chart_svg`: 5축 방사형(오각형) 차트를 JS 없이 서버 렌더 인라인 SVG(격자·스포크·데이터 폴리곤·축 라벨)로 반환.

---
> ⚠️ **유지보수 규칙**: 이 폴더의 파일이 추가·삭제되거나 역할이 바뀌면 이 CLAUDE.md도 함께 갱신하세요. 하위 폴더 구조가 바뀌면 관련 상·하위 CLAUDE.md 링크도 확인하세요.
