# app/controllers/ — 컨트롤러 계층 (요청 처리·인가·리다이렉트)

'책갈피'의 HTTP 요청을 받아 인가·조회·상태변경 후 뷰/Turbo Stream/JSON 으로 응답하는 계층입니다.
모든 컨트롤러는 `ApplicationController` 를 상속하며, 인가는 **Pundit**(정책·스코프)으로 처리합니다.
네임스페이스 없는 최상위 컨트롤러는 학생·공용 화면을, `admin/`·`teacher/`·`games/`·`librarian/`·`school_admin/`
하위 네임스페이스는 역할 전용 화면을 담당합니다. 라우트 근거는 [`config/routes.rb`](../../config/routes.rb) 참고.

## 파일
- `application_controller.rb` — 전 컨트롤러의 베이스. 로그인/정지/교사승인 세션 게이트 + `verify_authorized` fail-closed 인가 안전망 + Pundit 403 처리.
- `dashboard_controller.rb` — 루트(`/`). 역할별 홈 화면으로 분기 렌더(학생·교사·교무·사서). 총괄(superadmin)은 렌더 없이 `/admin` 콘솔로 리다이렉트.
- `reports_controller.rb` — 독후감 CRUD + `revise`(고쳐쓰기) + `share`(우수작 공유 토글). 제출 시 `AiReviewJob` 예약. index 는 페이지네이션(PER_PAGE=20). **revise 는 동일 본문 재첨삭 AI 호출을 스킵**(#misc): 부모 첨삭 결과(rubric/avg/level)를 이어받아 done 으로 시작하고, 학생이 본문을 고쳐 저장하면 update 의 `resubmit?` 가드(본문 변경 시에만)가 실제 재첨삭을 예약.
- `ocr_controller.rb` — 사진 업로드 → 손글씨 OCR 초안(`create`). Gemini 키 없으면 거부. 성공 시 `OcrJob` + Turbo Stream.
- `books_controller.rb` — 도서 카탈로그(`index`)·상세(`show`)·검색(`search`, 네이버 자동완성 JSON, 무키 시 로컬 폴백). index 는 페이지네이션(PER_PAGE=24)하고 **검색 upsert 캐시(`category: searched`)를 카탈로그에서 제외**해 무한 증가를 막는다(#2, searched 는 로컬 검색 폴백에서만 쓰임).
- `learn_controller.rb` — 단계 학습 위저드 5단계(`index`/`advance`). 세션 진행 저장, 완료 시 독후감 초안으로 프리필.
- `monsters_controller.rb` — 반려 몬스터 도감·상세 + `choose_starter`·`evolve`·`set_active`·`feed`(먹이/진화의 돌 소비).
- `shops_controller.rb` — 케어/진화 상점 조회(`show`). 잔액·인벤토리·카탈로그 표시(표현용).
- `purchases_controller.rb` — 상점 구매(`create`, 포인트 sink). 트랜잭션 원자 차감, Turbo Stream 응답.
- `rankings_controller.rb` — 랭킹·포디움·명예의 전당(`index`). tab = class/school/nation/challenge/hall.
- `missions_controller.rb` — 학급 미션 조회·참여(`join` → 세션 플래그로 다음 독후감에 연결).
- `challenges_controller.rb` — 전역/학교 챌린지 조회·참여(`join` → 세션 플래그로 다음 독후감에 연결).
- `board_posts_controller.rb` — 우수작 게시판(`index`/`show`). 학생 화면에서 숨김 글 제외(정책 스코프).
- `cheers_controller.rb` — 응원 👏(`create`/`destroy`). 1인 1회(unique) + Turbo Stream 버튼 갱신.
- `stickers_controller.rb` — 문장 스티커 동료평가(`create`). report 에 스티커 append(Turbo Stream).
- `topics_controller.rb` — 토론방(`index`/`show`/`create`). 학급/학교 스코프 경계로 생성.
- `forum_posts_controller.rb` — 토론 글 작성(`create`). 토픽 경계 안 사용자만 가능.
- `forum_post_likes_controller.rb` — 토론 글 좋아요 토글(`create`/`destroy`). 1인 1좋아요(unique, RecordNotUnique 무해 처리) + Turbo Stream 버튼 갱신(cheer 패턴).
- `sessions_controller.rb` — 로그인/로그아웃(튜플 신원: 학교·학급·이름·비번). **브루트포스 방어(#7, fail2ban+정답-우선)**: 먼저 인증해 **정답은 항상 로그인**시키고 IP·계정 실패 카운터를 리셋한다(피해자 계정 락아웃 DoS·전산실 NAT 동시로그인 차단을 동시 해소 — 정답은 실패로 안 세므로 NAT 뒤 학급 동시 로그인이 IP 한도에 안 걸린다). **오답만** 카운트하고 한도 초과 시 추가 오답(추측)을 락아웃한다(IP 3분 10회 / 계정 10분 8회). 계정 키는 조회된 **user.id 로 정규화**(존재 시)해 "5"/"05" 등 id 문자열 변형 우회를 막는다. 카운팅은 `RateLimiter`(Solid Cache 원자 increment, `count`/`record_failure`/`reset`) 재사용 — 가변 싱글턴 없이 경쟁 상태 제거. 저장소는 테스트 주입 시임(`self.rate_limit_store`)으로만 교체. `load_form_collections`는 학교 선택 하이브리드 피커용으로 전량 School/Classroom 로드 대신 `@regions`(시도교육청 distinct)만 로드(학급은 학교 선택 시 `/schools/:id/classrooms` 로 스코프 로드, 전국 전량 로드 제거).
- `registrations_controller.rb` — 공개 회원가입(교사 신청 전용, `approved:false`). 학급 배정까지 원자 처리. `load_form_collections`는 학교 선택 하이브리드 피커용으로 전량 School/Classroom 로드 대신 `@regions`(시도교육청 distinct)만 로드(전국 전량 로드 제거).
- `schools_controller.rb` — 학교 선택 하이브리드 피커용 공개 3액션. `search`(q 이름검색 + region/gu 필터, 상한 100)·`gus`(시도 region → 시군구 목록)·`classrooms`(선택 학교의 학급만 스코프 조회, 로그인 폼용). 가입/로그인 폼에서 사용.

`concerns/` 는 현재 `.keep` 플레이스홀더만 있어 공유 concern 이 없습니다(별도 CLAUDE.md 없음).

## 하위 폴더
- [`admin/`](admin/CLAUDE.md) — 총괄관리자(superadmin) 전용 `/admin` 네임스페이스. 전역 CRUD·통계·모더레이션.
- [`teacher/`](teacher/CLAUDE.md) — 담임교사 영역. 검토 큐·학생·미션·퀴즈·루브릭·문서출력·대시보드.
- [`games/`](games/CLAUDE.md) — 독서게임 5종(교육 다양성). quiz·classic·vocab·whoami(퀴즈 파이프라인) + book(소셜 도메인, Gemini 미호출).
- [`librarian/`](librarian/CLAUDE.md) — 사서 영역. 대시보드·이달의 책/행사·인기대출(정보나루/CSV).
- [`school_admin/`](school_admin/CLAUDE.md) — 교무관리자 영역. 전교 통계·NEIS 생기부 요약.

## 패턴·규칙
- **인가 안전망(fail-closed)**: `ApplicationController` 의 `after_action :verify_authorized` 가 authorize 미호출 액션을 예외로 실패시킨다. 공개·역할게이트·표현용 액션만 각 컨트롤러에서 이유를 달아 `skip_after_action :verify_authorized`(또는 `skip_authorization`)로 제외한다(예: dashboard·shops·sessions·registrations·schools).
- **최상위 = per-action Pundit**: 학생/공용 컨트롤러는 각 액션에서 `authorize`·`policy_scope` 를 직접 호출한다.
- **네임스페이스 = 역할 게이트**: 각 하위 `Base*Controller` 가 `require_*!` before_action 으로 역할을 일괄 검증하고 `verify_authorized` 를 스킵한다(단, `teacher/reviews` 는 예외로 per-action Pundit 사용).
- **세션 게이트**: 로그인·미정지·교사승인 여부를 매 요청 검사(정지/승인취소 시 즉시 로그아웃).

---
> ⚠️ **유지보수 규칙**: 이 폴더의 파일이 추가·삭제되거나 역할이 바뀌면 이 CLAUDE.md도 함께 갱신하세요. 하위 폴더 구조가 바뀌면 관련 상·하위 CLAUDE.md 링크도 확인하세요.
