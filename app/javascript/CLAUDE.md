# app/javascript/ — Stimulus 프런트엔드 (Hotwire + Import Maps)

브라우저에서 동작하는 모든 클라이언트 스크립트가 모입니다. 번들러·Node 빌드 없이 Import Maps로 모듈을 로드하며, 상호작용은 Turbo(서버 렌더 부분 갱신)와 Stimulus(경량 컨트롤러)로 처리합니다. 각 컨트롤러는 특정 UI 동작만 담당하는 작은 단위이고, 외부 라이브러리 의존 없이 순수 DOM/Canvas로 구현하는 것을 기본으로 합니다.

## 파일 / 하위 리소스
- `application.js` — 진입점. `@hotwired/turbo-rails`와 `controllers`를 import해 Turbo·Stimulus 부팅
- `controllers/index.js` — `controllers/**/*_controller`를 eager-load해 Stimulus에 자동 등록
- `controllers/application.js` — Stimulus `Application` 인스턴스 생성·export(`window.Stimulus`)
- `controllers/hello_controller.js` — Rails 기본 예제 컨트롤러(동작 확인용)
- `controllers/admin_sidebar_controller.js` — 총괄관리자 콘솔(`layouts/admin`)의 반응형 오프캔버스 사이드바 토글. 태블릿/모바일(<lg)에서 햄버거로 패널을 열고(`open`/`close`/`toggle`, `-translate-x-full`↔`translate-x-0`), backdrop 클릭·Escape(`keydown.esc@window`)로 닫으며 `aria-expanded` 갱신. 데스크톱(lg 이상)은 순수 CSS(`lg:static`)로 항상 노출 — JS 미로딩 시에도 그레이스풀
- `controllers/book_search_controller.js` — 도서 자동완성 + **선택**. 디바운스 입력을 서버로 fetch해 결과 목록을 렌더하고, 결과 클릭 시 hidden `book_id`·표시 input·표지를 세팅한 뒤 `book:selected` 커스텀 이벤트를 dispatch한다(퀴즈·게임·독후감 공용, 이벤트 계약 불변). **드롭다운 항목엔 고전 여부·장르 배지(`badgeElements`, 서버 `book_meta_badges`와 동일 `.badge` 스타일)를 붙인다** — 로컬 자동완성 응답의 `classic`/`genre` 필드 기반이며 원격(네이버) 결과엔 필드가 없어 자동 생략(그레이스풀). strict/fallback 모드 + `bookId`/`cover` 타깃은 선택적(없으면 표시 전용으로 동작). **시리즈 접기 2단계 드릴다운**: 결과 렌더의 `itemElement`가 디스패처로 분리돼 `series_count>1`(로컬 자동완성만 해당)이면 `seriesElement`("전 N권" 배지, `drillIntoSeries` 액션 — 즉시 선택하지 않음)를, 그 외(단권·원격·개별 권)는 기존처럼 즉시 `select`하는 `bookElement`를 렌더한다. `drillIntoSeries`가 신규 `volumesUrl` value(기본 `/books/volumes`)로 그 시리즈 전 권을 fetch해 `renderVolumes`("← 뒤로" 헤더 + 권별 "N권" 표식 목록)로 펼치고, 권 선택 시 그 권의 book_id로 확정한다. `backToResults`가 접힌 결과 목록(`lastResults`에 보관)으로 복귀시킨다. series_count가 없는 단권·원격 결과는 하위호환으로 기존과 동일하게 즉시 선택된다. **opt-in 원격검색 확장(하위호환)**: `remoteSearchUrl` value·`searchButton`/`isbn` 타깃이 있으면 검색 버튼(`manualSearch()`)이 **원격(네이버) 도서검색**을 `remoteSearchUrl`로 fetch(타이핑은 기존 `url`=로컬 autocomplete 그대로, 2-URL 분리·minChars 미강제). `select()`는 항목의 `id` 유무로 분기 — 로컬(id 보유)은 hidden `book_id` 세팅, 원격(id 없음+`isbn`)은 hidden `isbn`에 스태시하고 `book_id`는 공란(등록은 제출 시 서버가 수행, resolve/POST/async 없이 동기 유지). 셋 다 미설정이면 기존 동작과 완전히 동일
- `controllers/clipboard_controller.js` — 텍스트(NEIS 생기부 요약 등) 클립보드 복사 + "복사됨" 피드백
- `controllers/dex_controller.js` — 몬스터 도감 속성별 필터. 카드 표시 토글(순수 DOM)
- `controllers/growth_card_controller.js` — 독서 성장카드 PNG 내보내기. data-* 값을 Canvas에 그려 다운로드
- `controllers/monster_care_controller.js` — 먹이/진화 연출. 스프라이트에 bounce 애니메이션 클래스 토글
- `controllers/photo_upload_controller.js` — 사진 업로드 전 Canvas 클라이언트 압축 + 미리보기(불가 시 원본 전송)
- `controllers/report_edit_controller.js` — 고쳐쓰기(수정) 폼의 저장 버튼 dirty-check. 본문 textarea 를 원본과 비교해 **달라졌을 때만 "수정하기" 버튼 활성화**(`resubmit?` 본문-변경 재첨삭 가드와 짝). 기존 글 폼(`report.persisted?`)에만 부착하고, OCR 초안으로 textarea 가 교체돼도 기준값 유지. JS 미로딩 시 버튼은 그대로 활성(그레이스풀)
- `controllers/school_picker_controller.js` — 학교 선택 하이브리드 피커. 시도→시군구 캐스케이딩(`/schools/gus`)은 native `<select>`를 채우고, **이름검색(`/schools/search`)은 목록형 드롭다운(`<li>` 클릭 선택)**으로 결과를 띄워 클릭 시 hidden `school_id`를 세팅한다. gu 가 비거나 부정확해도 이름검색으로 항상 도달(graceful degrade). 로그인 폼(classroom 타깃 존재)이면 선택 학교의 학급을 `/schools/:id/classrooms` 로 캐스케이딩 스코프 로드. **학년도 select(`academicYear` 타깃, 마이그레이션 #38)**: 학급 조회 URL 에 `?academic_year=` 를 부착(`academicYearQuery`)해 같은 반 번호의 학년도 중복을 구분하고, 학년도를 바꾸면(`academicYearChanged`) 이미 학교를 골랐을 때만 학급을 재조회한다. 타깃이 없으면(가입 폼 등) 쿼리 미부착·전 학년도(그레이스풀)
- `controllers/games_catalog_controller.js` — 게임 카탈로그. `book:selected`(book_search) 이벤트를 구독해 5종 게임 칩을 활성화하고 각 칩의 진입 링크에 선택된 `book_id`를 세팅
- `controllers/discovery_controller.js` — 몬스터 발견 연출 모달. 미연출 몬스터 큐를 순차 등장 애니메이션으로 보여 주고, 표시 즉시 `discoveries/acknowledge` fetch로 celebrated_at 을 마킹(재노출 방지)
- `controllers/report_guide_controller.js` — **직접쓰기 안내 질문 단계(요구 1a)**. 밴드별 질문 답변(name 없는 answer 타깃 textarea)을 `assemble()`가 trim·빈 제외·`\n\n` join 해 숨겨진 `_form`의 `#report_body_field`에 주입(`input`/`change` 이벤트 dispatch로 리스너 호환)하고 질문 패널을 접어 폼을 노출한다. 답변은 `localStorage`(키 `guided:<userId||anon>:<bookKey>`)에 저장해 학생별로 격리·"이어서 쓰기" 복원, assemble/제출 성공 시 클리어. localStorage 접근은 try/catch 그레이스풀, JS 미로딩 시 질문·폼이 함께 보여 직접 작성 가능
- `controllers/guide_modal_controller.js` — **사진쓰기 가이드 모달(요구 1b)**. `_photo_guide`의 자가점검 안내 카드를 connect 시 오버레이 dialog 로 승격·자동 오픈하고, "확인했어요" 버튼·Escape·배경 클릭·"작성 팁 다시 보기"로 여닫는다. `turbo:before-cache`에 상태 리셋. JS 미로딩 시 그냥 보이는 안내 카드로 완전 동작(그레이스풀)
- `controllers/student_nav_controller.js` — 학생 공용 네비의 모바일 `<details>` disclosure 보조. 메뉴 링크 선택·바깥 클릭·Escape 에서 닫고(Escape 는 summary 로 포커스 복원), `turbo:before-cache` 전에 열린 상태를 초기화한다. 열기/닫기 기본 동작은 네이티브 `<details>/<summary>`가 맡아 JS 미로딩 시에도 메뉴 접근 가능

## 패턴·규칙
- **자동 등록**: 새 컨트롤러는 `controllers/이름_controller.js`로 추가하면 `index.js`의 eager-load가 자동 인식. 수동 등록 불필요.
- **경량·무의존**: 외부 npm 패키지 없이 순수 DOM/Canvas/Fetch로 구현. `static targets`·`static values`로 뷰의 `data-*`와 연결.
- **그레이스풀 폴백**: 클립보드·이미지 압축 등 브라우저 API 미지원 환경에서 원본 전송/폴백 경로를 둠.
- **역할 분담**: 서버 렌더 부분 갱신은 Turbo Stream(뷰의 `.turbo_stream.erb`)이 맡고, JS는 순수 클라이언트 상호작용(입력 보조·연출·내보내기)만 담당.

---
> ⚠️ **유지보수 규칙**: 이 폴더의 파일이 추가·삭제되거나 역할이 바뀌면 이 CLAUDE.md도 함께 갱신하세요. 하위 폴더 구조가 바뀌면 관련 상·하위 CLAUDE.md 링크도 확인하세요.
