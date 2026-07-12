# test/ — Minitest + Capybara 테스트 스위트 (약 636 runs)

'책갈피'(Rails 8.1)의 전체 자동화 테스트 모음이다. 모델·정책·서비스 단위 테스트부터 역할별 화면·플로우를 검증하는 integration 테스트까지 포함한다. 테스트는 **외부 API를 절대 호출하지 않으며**(`test_helper.rb`가 credentials 키를 공란으로 강제 → 도서검색·정보나루·Gemini가 오프라인 폴백 경로를 탄다), 원격 성공 경로는 스텁 커넥션을 DI로 주입해 검증한다.

## 하위 카테고리
- `test_helper.rb` — 공통 설정. 외부 키 공란 강제(오프라인 폴백), 병렬 실행, `fixtures :all`, 헬퍼 `seed_monster_species!`(24라인×3단계=72폼 시드)·`seed_badges!`(뱃지 13종).
- `models/` — 모델 단위: 뱃지·도서·학급·학교·리포트·토픽·유저·몬스터종·유저몬스터, 게임화/퀴즈 데이터 모델, 몬스터 시드 무결성, 마이그레이션 FK 존재 검증. **Phase 6 보강(#5)**: `library_loan`·`library_event`·`user_badge`·`forum_post` 모델 검증, `app_setting`(API 키 저장 차단 보안검증 추가), `monster_seed_integrity`(스타터 3종 정합), **`fk_on_delete_roundtrip`**(reports→books·monster_species 자기참조 on_delete nullify 동작 + SQLite up/down 왕복 무손실; 이 파일만 `use_transactional_tests = false` — DDL 커밋 후 teardown 에서 up 복원·행 정리).
- `models/concerns/` — 공유 모듈: `Badgeable`·`Evolvable`·`Leveling`·`Pointable`·`RubricScorable`.
- `controllers/` — 컨트롤러 공용 로직 단위: `axis_averages_parity`(전교 5축 SQL 집계 == 인메모리 집계 parity, #3).
- `tasks/` — rake 시드 태스크: `quizzes_seed`(샘플 퀴즈가 Phase 1 콘텐츠축 컬럼 반영·멱등 재현, #9-seed).
- `policies/` — Pundit 인가. `authorization_matrix_test.rb`가 역할×액션 경계 회귀 매트릭스, 개별 정책(cheer·classroom·report·sticker·topic)이 스코프/권한 세부.
- `services/ai/` — Gemini 클라이언트·OCR·퀴즈 초안·첨삭(review)·규칙기반 첨삭·검증(verify). 무키 시 규칙기반 폴백 + 스텁 성공 경로.
- `services/books/`·`services/library/` — 도서 검색(네이버) 및 정보나루(data4library) 서비스: 무키 폴백·정규화·파싱.
- `services/games/`·기타 서비스 — 퀴즈 플레이 멱등 적립(포인트 파밍 차단), 몬스터 획득, 랭킹 집계, 독서 통계.
- `jobs/` — 백그라운드 잡: `AiReviewJob`(AI 첨삭)·`OcrJob`(사진 OCR).
- `helpers/` — 뷰 헬퍼(`TeacherHelper`).
- `integration/` — 역할별 화면·플로우 E2E(대표 그룹은 아래).
- `fixtures/files/` — 테스트 자산. 현재 `handwriting.png`(OCR 입력 이미지)만 있음. YAML 픽스처는 사용하지 않고, 데이터는 각 테스트의 `setup`/시더로 생성.

## integration/ 대표 그룹
- **인증·역할 진입**: `registrations`(교사 신청+승인 게이트)·`sessions`·`dashboard_access`·`dashboard_role`·`board_posts`·`schools_search`·`topics`·`books_catalog`.
- **독후감 파이프라인**: `report_review_flow`(Phase 3 완료 게이트)·`reports`·`ocr`(사진→텍스트)·`learn_wizard`(단계 학습 위저드).
- **게임화·반려 몬스터**: `games`(독서게임 10종)·`game_points_flow`·`rankings`·`starter_selection`·`monster_evolution`·`monster_feed`·`mission_participation`·`shop_purchase`.
- **교사(P6)**: `teacher_dashboard`·`teacher_missions`·`teacher_quizzes`·`teacher_reviews`·`teacher_students`·`teacher_rubric_config`·`teacher_exports`(CSV)·`teacher_prints`(인쇄 문서).
- **사서(P6.5)**: `librarian_dashboard`·`librarian_events`·`librarian_loans`(정보나루 동기화).
- **교무관리자**: `school_admin_neis`(생기부 요약)·`school_admin_stats`(전교 통계·학교 경계).
- **총괄관리자(P7)**: `admin_isolation`(superadmin 전용 격리)·`admin_users`·`admin_content`·`admin_settings`(API 키 저장 금지 가드)·`admin_moderation`·`admin_analytics`·`admin_monster_species`.
- **인가 안전망·보안**: `authorization_safety_net`(fail-closed, authorize 누락 감지)·`content_security_policy`.
- **Phase 6 하드닝(#2·#4·#7·#9·misc)**: `books_catalog`(카탈로그 페이지네이션 + `searched` 캐시 제외)·`admin_moderation`(3섹션 페이지네이션)·`admin_users`(포인트 조정 award_points 델타 경유 — 랭킹 후크 발화·하향 원자 차감)·`sessions`(계정 단위 스로틀+락아웃, RateLimiter 원자 increment 주입 시임)·`reports`(고쳐쓰기 동일 본문 재첨삭 스킵·본문 수정 시 재예약).

## 패턴·규칙
- 실행: `bin/rails test` (전체, 약 497 runs). 단일 파일은 `bin/rails test test/경로/파일_test.rb`.
- 품질 게이트: `bin/ci`가 순서대로 `bin/rubocop`(스타일) → `bin/bundler-audit`·`bin/importmap audit`·`bin/brakeman`(보안) → `bin/rails test`(테스트) → `db:seed:replant`(시드 재적재)를 실행. PR은 이 전 단계가 통과해야 한다.
- 테스트는 병렬(`parallelize`) 실행되므로 전역 상태에 의존하지 말 것.
- 몬스터/뱃지가 필요한 테스트는 `setup`에서 `seed_monster_species!`·`seed_badges!`를 호출(트랜잭션 롤백되며 멱등).

---
> ⚠️ **유지보수 규칙**: 이 폴더의 파일이 추가·삭제되거나 역할이 바뀌면 이 CLAUDE.md도 함께 갱신하세요. 하위 폴더 구조가 바뀌면 관련 상·하위 CLAUDE.md 링크도 확인하세요.
