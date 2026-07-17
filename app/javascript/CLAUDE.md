# app/javascript/ — Stimulus 프런트엔드 (Hotwire + Import Maps)

브라우저에서 동작하는 모든 클라이언트 스크립트가 모입니다. 번들러·Node 빌드 없이 Import Maps로 모듈을 로드하며, 상호작용은 Turbo(서버 렌더 부분 갱신)와 Stimulus(경량 컨트롤러)로 처리합니다. 각 컨트롤러는 특정 UI 동작만 담당하는 작은 단위이고, 외부 라이브러리 의존 없이 순수 DOM/Canvas로 구현하는 것을 기본으로 합니다.

## 파일 / 하위 리소스
- `application.js` — 진입점. `@hotwired/turbo-rails`와 `controllers`를 import해 Turbo·Stimulus 부팅
- `controllers/index.js` — `controllers/**/*_controller`를 eager-load해 Stimulus에 자동 등록
- `controllers/application.js` — Stimulus `Application` 인스턴스 생성·export(`window.Stimulus`)
- `controllers/hello_controller.js` — Rails 기본 예제 컨트롤러(동작 확인용)
- `controllers/admin_sidebar_controller.js` — 총괄관리자 콘솔(`layouts/admin`)의 반응형 오프캔버스 사이드바 토글. 태블릿/모바일(<lg)에서 햄버거로 패널을 열고(`open`/`close`/`toggle`, `-translate-x-full`↔`translate-x-0`), backdrop 클릭·Escape(`keydown.esc@window`)로 닫으며 `aria-expanded` 갱신. 데스크톱(lg 이상)은 순수 CSS(`lg:static`)로 항상 노출 — JS 미로딩 시에도 그레이스풀
- `controllers/book_search_controller.js` — `/books/search` 자동완성. 디바운스 입력을 서버로 fetch해 결과 목록 렌더
- `controllers/clipboard_controller.js` — 텍스트(NEIS 생기부 요약 등) 클립보드 복사 + "복사됨" 피드백
- `controllers/dex_controller.js` — 몬스터 도감 속성별 필터. 카드 표시 토글(순수 DOM)
- `controllers/growth_card_controller.js` — 독서 성장카드 PNG 내보내기. data-* 값을 Canvas에 그려 다운로드
- `controllers/monster_care_controller.js` — 먹이/진화 연출. 스프라이트에 bounce 애니메이션 클래스 토글
- `controllers/photo_upload_controller.js` — 사진 업로드 전 Canvas 클라이언트 압축 + 미리보기(불가 시 원본 전송)
- `controllers/report_edit_controller.js` — 고쳐쓰기(수정) 폼의 저장 버튼 dirty-check. 본문 textarea 를 원본과 비교해 **달라졌을 때만 "수정하기" 버튼 활성화**(`resubmit?` 본문-변경 재첨삭 가드와 짝). 기존 글 폼(`report.persisted?`)에만 부착하고, OCR 초안으로 textarea 가 교체돼도 기준값 유지. JS 미로딩 시 버튼은 그대로 활성(그레이스풀)
- `controllers/school_picker_controller.js` — 학교 선택 하이브리드 피커. 시도→시군구 캐스케이딩(`/schools/gus`)과 이름검색(`/schools/search`)이 같은 학교 셀렉트를 채우며, gu 가 비거나 부정확해도 이름검색으로 항상 도달(graceful degrade). 로그인 폼(classroom 타깃 존재)이면 선택 학교의 학급을 `/schools/:id/classrooms` 로 스코프 로드
- `controllers/student_nav_controller.js` — 학생 공용 네비의 모바일 `<details>` disclosure 보조. 메뉴 링크 선택·바깥 클릭·Escape 에서 닫고(Escape 는 summary 로 포커스 복원), `turbo:before-cache` 전에 열린 상태를 초기화한다. 열기/닫기 기본 동작은 네이티브 `<details>/<summary>`가 맡아 JS 미로딩 시에도 메뉴 접근 가능

## 패턴·규칙
- **자동 등록**: 새 컨트롤러는 `controllers/이름_controller.js`로 추가하면 `index.js`의 eager-load가 자동 인식. 수동 등록 불필요.
- **경량·무의존**: 외부 npm 패키지 없이 순수 DOM/Canvas/Fetch로 구현. `static targets`·`static values`로 뷰의 `data-*`와 연결.
- **그레이스풀 폴백**: 클립보드·이미지 압축 등 브라우저 API 미지원 환경에서 원본 전송/폴백 경로를 둠.
- **역할 분담**: 서버 렌더 부분 갱신은 Turbo Stream(뷰의 `.turbo_stream.erb`)이 맡고, JS는 순수 클라이언트 상호작용(입력 보조·연출·내보내기)만 담당.

---
> ⚠️ **유지보수 규칙**: 이 폴더의 파일이 추가·삭제되거나 역할이 바뀌면 이 CLAUDE.md도 함께 갱신하세요. 하위 폴더 구조가 바뀌면 관련 상·하위 CLAUDE.md 링크도 확인하세요.
