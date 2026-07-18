# test/ — Minitest + Capybara 테스트 스위트 (857 runs)

'책갈피'(Rails 8.1)의 전체 자동화 테스트 모음이다. 모델·정책·서비스 단위 테스트부터 역할별 화면·플로우를 검증하는 integration 테스트까지 포함한다. 테스트는 **외부 API를 절대 호출하지 않으며**(`test_helper.rb`가 credentials 키를 공란으로 강제 → 도서검색·정보나루·Gemini가 오프라인 폴백 경로를 탄다), 원격 성공 경로는 스텁 커넥션을 DI로 주입해 검증한다.

## 하위 카테고리
- `test_helper.rb` — 공통 설정. 외부 키 공란 강제(오프라인 폴백), 병렬 실행, `fixtures :all`, `seed_monster_species!`·`seed_badges!`·`login_as(user)` 및 `xlsx_test_helper.rb`의 최소 XLSX 생성기를 포함한다.
- `models/` — 모델 단위: 뱃지·도서·학급·학교·리포트·토픽·유저·몬스터종·유저몬스터, 게임화/퀴즈 데이터 모델(`quiz_question`의 1-based `answer_number` 가상 접근자 포함), **`game_play`**(부분 유니크 인덱스 2종의 일일 dedup — book 있는/없는 플레이 각각), 몬스터 시드 무결성, 마이그레이션 FK 존재 검증. **Phase 6 보강(#5)**: `library_loan`·`library_event`·`user_badge`·`forum_post`·`forum_post_like`(좋아요 uniqueness·likes_count counter_cache 증감) 모델 검증, `app_setting`(API 키 저장 차단 보안검증 추가), `monster_seed_integrity`(스타터 3종 정합 + `image_key` WebP 72종의 누락·잔존 파일 검증), **`fk_on_delete_roundtrip`**(reports→books·monster_species 자기참조 on_delete nullify 동작 + SQLite up/down 왕복 무손실; 이 파일만 `use_transactional_tests = false` — DDL 커밋 후 teardown 에서 up 복원·행 정리). **`monster_species`**는 `unlock_condition` JSON 검증(evolve_condition과 별개 컬럼·화이트리스트 공유)도 함께 커버한다.
- `models/concerns/` — 공유 모듈: `Badgeable`·`Evolvable`·`Leveling`·`Pointable`·`RubricScorable`.
- `controllers/` — 컨트롤러 공용 로직 단위: `axis_averages_parity`(전교 5축 SQL 집계 == 인메모리 집계 parity, #3).
- `tasks/` — rake 시드 태스크: `quizzes_seed`(샘플 퀴즈 멱등 재현)·`schools_seed`(전량 CSV 헤더/필수값/전국 검증, 배치 upsert, 멱등 갱신, 누락 NEIS·구 합성 학교 비활성화, manual 보존, 파일 미존재 no-op)·`books_seed`(`books:enrich` 큐레이션 보강)·`books_seed_full`(TSV 전량 적재 검증).
- `policies/` — Pundit 인가. `authorization_matrix_test.rb`가 역할×액션 경계 회귀 매트릭스, 개별 정책(cheer·classroom·report·sticker·topic)이 스코프/권한 세부.
- `services/ai/` — Gemini 클라이언트·OCR·퀴즈 초안·첨삭(review)·규칙기반 첨삭·검증(verify). 무키 시 규칙기반 폴백 + 스텁 성공 경로.
- `services/books/`·`services/library/` — 도서 검색(네이버) 및 정보나루(data4library) 서비스: 무키 폴백·정규화·파싱. `services/books/`는 `search_service` + **`catalog_enricher`**(큐레이션 보강, service/throttle DI, 무키 no-op) + **`genre_inference`**(무API 장르 추론 — n-gram kNN·STRONG_GENRE_RULES) 3파일.
- `services/schools/` — NEIS 학교기본정보 연동: `gu_parser`(도농복합시·단층제·시도 토큰 생략)·`neis_fetcher`(전체 건수 페이지네이션, 후속 페이지 실패/HTTP 200 API 오류/국내 필터)·`snapshot_validator`(필수값·중복·전국 최소 건수·17개 교육청).
- `services/recommendations/` — 실제 번들 XLSX의 어린이 분과 203권 파싱 계약, ISBN upsert, 청소년 제외, digest 멱등, 활성 목록 교체, 실패 롤백을 검증한다.
- `services/games/`·기타 서비스 — 퀴즈 플레이 멱등 적립(포인트 파밍 차단), 몬스터 획득, 랭킹 집계, 독서 통계(`reading_stats` — `max_daily_reports`·`game_plays`/`distinct_games`/`game_books` 신규 지표 포함). **`monster_unlock`**(fixpoint 캐스케이드 — dex_count 20 도달 시 같은 `evaluate!` 호출에서 dex 24 동시 해금, AND 다중조건, 멱등 재실행, 라인 지급 실패 rescue).
- `jobs/` — 백그라운드 잡: `AiReviewJob`(AI 첨삭)·`OcrJob`(사진 OCR)·`BookEnrichmentJob`(무API genre 보강 — 공란만 채움·멱등).
- `helpers/` — 뷰 헬퍼(`TeacherHelper`, `MonstersHelper`의 WebP 렌더·이모지 폴백).
- `integration/` — 역할별 화면·플로우 E2E(대표 그룹은 아래).
- `fixtures/files/` — 테스트 자산. `handwriting.png`(OCR 입력 이미지)·`schools_sample.csv`(NEIS 전량 시드 파싱용 샘플). YAML 픽스처는 사용하지 않고, 데이터는 각 테스트의 `setup`/시더로 생성.

## integration/ 대표 그룹
- **인증·역할 진입**: `registrations`(교사 회원가입+**이메일 필수**+가입 즉시 로그인)·`sessions`(**로그인 표면 2분화** — 안내 인덱스 선택 화면 + 학생 튜플 로그인 + 교직원 이메일 로그인 + 표면 교차 차단 + 스로틀)·`passwords`(본인 비밀번호 변경 — 현재 비번 확인 성공/실패·fail-closed·역할무관)·`dashboard_access`·`dashboard_role`·`board_posts`·`schools_search`·`school_picker`(학교 목록형 검색→선택→학급 캐스케이딩)·`topics`·`forum_post_likes`(게시판 글 좋아요 토글·1인 1좋아요·학급 경계 차단·로그인 게이트)·`books_catalog`·`books_autocomplete`(로컬 비-searched 자동완성 스코프·응답 id).
- **독후감 파이프라인**: `report_review_flow`(Phase 3 완료 게이트)·`reports`·`reports_book_link`(자동완성 선택 시 `book_id` 연결·표지 표시·미선택 book_title 폴백)·`ocr`(사진→텍스트, 모드선택 후 redirect·거부 가드)·`report_input_mode`(새 글 모드 선택 chooser/keyboard/photo 3분기 + 위저드 프리필 보존)·`report_first_review`(OCR 초안 첫 제출 첨삭 예약·revise 스킵·빈본문 레이스 가드)·`ocr_book_reference`(도서 참조 없으면 draft 미생성·500 아님)·`learn_wizard`(단계 학습 위저드).
- **게임화·반려 몬스터**: `games`(독서게임 5종 — 퀴즈 4종 실동작)·`games_catalog`(카탈로그 재구성 — 도서 검색 + 게임 칩 렌더)·`games_ondemand`(온디맨드 e2e)·`games_authorization`(경계 클램프)·`games_book_intro`(책 소개 대결 — 소셜·1인 1표·크로스학급 차단·Gemini/Quiz 미생성 assert)·`game_points_flow`·`rankings`·`starter_selection`·`monster_evolution`·`monster_feed`·`discovery_modal`(발견 연출 드레인 — `pending_celebration` 노출·acknowledge 멱등 마킹·교사 승인→학생 노출)·`mission_participation`·`shop_purchase`·**`monster_unlock_flow`**(독후감 승인·게임 완료 트리거 배선 e2e — 승인 시 해금+flash, `game_plays` 원장 기록[표면·책·일자], game_type allowlist 밖 값 미기록, 동일 퀴즈 재제출 dedup, 게임 완료로 해금 임계 도달 시 발견)·`student_nav_persistence`(학생 상단 navbar가 7개 메뉴 페이지[내 서재·독후감·게임·도감·상점·미션·랭킹] 전체에서 모바일 disclosure/데스크톱 필 목록·동일 경로·활성 탭 강조를 유지하고, 메뉴 페이지의 중복 제목 제거와 독후감 작성 액션·상점 포인트의 navbar 직후 배치를 검증).
- **교사(P6)**: `teacher_dashboard`·`teacher_missions`·`teacher_quizzes`·`teacher_reviews`·`teacher_students`·`teacher_rubric_config`·`teacher_exports`(CSV)·`teacher_prints`(인쇄 문서).
- **사서(P6.5)**: `librarian_dashboard`·`librarian_events`·`librarian_loans`(정보나루 동기화).
- **교무관리자**: `school_admin_neis`(생기부 요약)·`school_admin_stats`(전교 통계·학교 경계).
- **총괄관리자(P7)**: `admin_isolation`(superadmin 전용 격리)·`admin_users`·`admin_content`·`admin_settings`(API 키 저장 금지 가드)·`admin_moderation`·`admin_analytics`·`admin_monster_species`.
- **인가 안전망·보안**: `authorization_safety_net`(fail-closed, authorize 누락 감지)·`content_security_policy`.
- **Phase 6 하드닝(#2·#4·#7·#9·misc)**: `books_catalog`(카탈로그 페이지네이션 + `searched` 캐시 제외)·`admin_moderation`(3섹션 페이지네이션)·`admin_users`(포인트 조정 award_points 델타 경유 — 랭킹 후크 발화·하향 원자 차감)·`sessions`(계정 단위 스로틀+락아웃, RateLimiter 원자 increment 주입 시임)·`reports`(고쳐쓰기 동일 본문 재첨삭 스킵·본문 수정 시 재예약·작성자 전용 목록 삭제).

## 패턴·규칙
- 실행: `bin/rails test` (전체, 857 runs). 단일 파일은 `bin/rails test test/경로/파일_test.rb`.
- 품질 게이트: `bin/ci`가 순서대로 `bin/rubocop`(스타일) → `bin/bundler-audit`·`bin/importmap audit`·`bin/brakeman`(보안) → `bin/rails test`(테스트) → `db:seed:replant`(시드 재적재)를 실행. PR은 이 전 단계가 통과해야 한다.
- 테스트는 병렬(`parallelize`) 실행되므로 전역 상태에 의존하지 말 것.
- 몬스터/뱃지가 필요한 테스트는 `setup`에서 `seed_monster_species!`·`seed_badges!`를 호출(트랜잭션 롤백되며 멱등).

---
> ⚠️ **유지보수 규칙**: 이 폴더의 파일이 추가·삭제되거나 역할이 바뀌면 이 CLAUDE.md도 함께 갱신하세요. 하위 폴더 구조가 바뀌면 관련 상·하위 CLAUDE.md 링크도 확인하세요.
