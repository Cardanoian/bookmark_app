# config/ — Rails 8.1 애플리케이션 설정

'책갈피'의 부팅·라우팅·다중 DB·백그라운드 인프라(Solid Queue/Cache/Cable)·배포(Kamal)·보안 정책을 모아 둔 폴더입니다. Rails 8.1 기본값(`config.load_defaults 8.1`)을 따르며, 외부 API 키는 코드/YAML 에 두지 않고 암호화된 credentials(또는 배포 시 ENV)로만 공급합니다.

## routes.rb — 라우팅 지도(가장 중요)

`root`은 `dashboard#show`. **인증은 로그인 표면이 둘로 분리**된다: 처음 접속 시 `session#new`(GET `/session/new`, `new_session_path`)가 **안내 인덱스**(학생/교직원 선택 화면)를 렌더하고, 비로그인 리다이렉트(`require_login`)도 이 경로로 온다. 실제 로그인은 ① **학생** `login/student`(GET `sessions#student_new` = 튜플 신원 폼 / POST `sessions#student_create`, `student_login_path`)와 ② **교직원**(교사·교무관리자·사서·총괄관리자) `login/staff`(GET `sessions#staff_new` = 이메일 폼 / POST `sessions#staff_create`, `staff_login_path`)로 나뉜다. 로그아웃은 공용 `DELETE /session`(`session_path`, `sessions#destroy`). 교사 가입(`registrations`)은 이메일을 필수로 받는다(교직원은 이메일로 로그인). 학교 선택 하이브리드 피커용으로 `schools/search`(이름검색) 옆에 `schools/gus`(시도→시군구 목록)·`schools/:id/classrooms`(학생 로그인 종속 학급 스코프 조회)가 별도 GET 으로 존재. 크게 **학생용 최상위 리소스**와 **역할별 네임스페이스**로 나뉩니다.

- **학생 영역(최상위)**
  - `reports` — 독후감 CRUD + `revise`(고쳐쓰기)·`share`(공유) member 액션, `ocr`(사진 손글씨 인식) singular 리소스.
  - `books`(index/show + `search`·`autocomplete`·`remote_search` collection) — 도서 검색·카탈로그. `search`는 네이버+로컬폴백(응답에 로컬 `id` 포함), `autocomplete`는 로컬 카탈로그(비-searched)만 조회하는 도서 자동완성(외부호출 0, 퀴즈·게임 도서 선택용), **`remote_search`(`remote_search_books_path`)는 독후감 새 글 "🔍 검색" 버튼 전용 네이버 도서검색**(서버가 `book_meta:<isbn>` 캐시 적재→제출 시 `SearchService#register` 재사용, 무키/실패 시 [](로컬 폴백 없음 — 타이핑 autocomplete 와 분리)).
  - `learn`(index + `advance`) — 5단계 단계학습 위저드.
  - **`library`**(singular, `libraries#show`) — 내 서재(책별 활동 포트폴리오) · **`reading_activity`**(singular, `reading_activities#show`) — 독서활동 허브(책 선택→독후감/게임). menu_refactor 심화 PR5 학생 상위 메뉴(홈·내 서재·독서활동·도감·랭킹) 정보구조.
  - `namespace :games` — 독서게임 5종(Phase 3 온디맨드 + 소셜). **카탈로그** `games/catalog`(도서→게임 진입 관문) + **퀴즈 파이프라인 4종 표면의 `<표면>/play`**(book_id 온디맨드 진입; quiz·classic·vocab·whoami) + quiz 의 교사 published mcq 퀴즈 `:id` show 병행 + whoami `:id` show(=attempt 상태) 와 **`whoami/:attempt/reveal_hint`**(POST, 서버 힌트 공개) + **책 소개 대결** `book/play`(GET, 도서별 소개 목록·작성 폼)·`book/intros`(POST 작성)·`book/intros/:id/vote`(POST/DELETE 또래 1인 1표) + **`regenerate`**(POST, 다시 뽑기=콘텐츠 재생성; 무가챠 라우트 가드 준수차 `roll` 어휘 회피) + **`content_reports`**(POST, 콘텐츠 신고=무게이트 롤아웃 안전장치; system 판 `quiz_id`, 서로 다른 2명 시 자동 숨김+재생성) + 결과 기록용 `attempts#create`(퀴즈 4종). `play/…play` 라우트를 `:id` show 보다 먼저 선언해 "play" 가 id 로 오인되지 않게 한다. book 은 퀴즈 파이프라인 밖 소셜 도메인(Gemini/Quiz 미생성).
  - 커뮤니티 — `board_posts`(우수작, 중첩 `cheers`·`stickers`) + `topics`(토론방, 중첩 `forum_posts`).
  - 게임화 — `monsters`(도감/`evolve`·`set_active`·`choose_starter`), `rankings`, `challenges`(`join`) + `discoveries/acknowledge`(POST, `acknowledge_discoveries_path`) 몬스터 발견 연출 확인 후 celebrated_at 마킹(재노출 방지). **미션은 자동 배정·자동 진행이라 학생 `missions`·`join` 라우트가 없다**(menu_refactor 심화 PR6 — 홈·독서활동 문맥 카드로 노출). **상점(`shop`·`purchases`)·먹이(`feed`)는 PR7/8 에서 제거**.
  - 계정 — `profile/password`(GET passwords#edit / PATCH passwords#update, `edit_password_path`/`password_path`) 본인 비밀번호 변경(역할무관, 현재 비번 확인 후 변경).
- **역할별 네임스페이스** (컨트롤러 `Xxx::BaseController` 가 자기 학교/권한 경계를 가드)
  - `namespace :teacher` — 담임교사. `dashboard`, 검토 큐 `reviews`(`approve`·`verify`·`batch_approve`), `students`(`reset_password`·`give_points`), `missions`·`quizzes`, `rubric_config`, 문서출력(`exports#reports_csv` + `prints` 의 표창장·가정통신문·포트폴리오·학급리포트).
  - `namespace :school_admin` — 교무관리자. `stats`, `neis`(생기부 자동요약). 자기 학교 경계.
  - `namespace :librarian` — 사서. `dashboard`, `events`, `loans`(`sync_data4library`·`import_csv`). 자기 학교 경계.
  - `namespace :admin` — 총괄관리자(superadmin) 전용. root=`analytics#show`, 전 자원 관리(`schools`·`users`·`books`·`recommendation_imports`[XLSX index/create]·`quizzes`·`badges`·`shop_items`·`monster_species`·`moderation`·`settings`·`analytics`). `Admin::BaseController` 가 superadmin 외 전 역할 403.
- 그 외 `/up` = 헬스체크(`rails/health#show`), PWA 라우트는 주석 처리(비활성).

## 파일

- `application.rb` — 앱 전역 설정. `load_defaults 8.1`, `autoload_lib(ignore: %w[assets tasks])` 로 `lib/tasks` 를 오토로드 제외.
- `boot.rb` — Bundler 셋업 + bootsnap 캐시로 부팅 가속.
- `environment.rb` — `application.rb` 로드 후 `Rails.application.initialize!` 호출(부팅 마지막 단계).
- `database.yml` — SQLite 다중 DB. development/test 는 단일 primary, **production 은 primary·cache·queue·cable 4개 DB**(각각 별도 파일 + `db/*_migrate` 마이그레이션 경로).
- `puma.rb` — 웹 서버. 스레드 수 `RAILS_MAX_THREADS`(기본 3), `SOLID_QUEUE_IN_PUMA` 설정 시 Puma 안에서 Solid Queue 수퍼바이저 구동.
- `cable.yml` — Action Cable. development=async, production=`solid_cable`(cable DB).
- `cache.yml` — Solid Cache. 항목당 max_size 256MB, production 은 cache DB 사용.
- `queue.yml` — Solid Queue 디스패처/워커(모든 큐, 스레드 3, `JOB_CONCURRENCY` 프로세스).
- `recurring.yml` — Solid Queue 반복 작업(production). 매시 완료 잡 정리 + **미션 완료·보상 주기 재평가**(`Missions::ReevaluateJob`, menu_refactor 심화 §2.A.6 안전망2 — 이벤트 훅 미스·지연배정 갭 백스톱, Rewarder 멱등이라 재실행 안전). dev/test 는 production 전용이라 즉시 평가 + 수동 `missions:reevaluate` rake 로 커버.
- `storage.yml` — Active Storage 서비스(local=Disk, test=임시). S3/GCS 는 주석 예시.
- `importmap.rb` — importmap-rails 핀(turbo·stimulus + `app/javascript/controllers`). 자체 호스팅, 외부 CDN 미사용.
- `deploy.yml` — Kamal 배포 매니페스트. 서비스명 `bookmark_app`, SSL 자동(Let's Encrypt), 로컬 레지스트리(`localhost:5555`), 영구 볼륨(`/rails/storage`). 시크릿 ENV 는 **`RAILS_MASTER_KEY` 하나뿐**(이 키로 컨테이너가 credentials 를 복호화해 API 키를 런타임에 읽음 — 단일 소스). API 키를 서버 ENV 로 우회 주입하지 않는다(`docs/API_KEYS.md` §6). `.kamal/secrets` 도 `RAILS_MASTER_KEY` 한 줄만 담는다.
- `ci.rb` — `bin/ci` 파이프라인(rubocop·bundler-audit·importmap audit·brakeman·rails test·seed replant).
- `bundler-audit.yml` — 젬 취약점 감사 무시 목록(CVE allowlist).
- `credentials.yml.enc` — **보안 파일**. 외부 API 키 등 암호화 저장소. `master.key` 없이 복호화 불가. `bin/rails credentials:edit` 로만 편집하고 내용을 열거나 커밋 로그에 노출하지 말 것.
- `master.key` — **보안 파일**. credentials 복호화 키(32바이트). `.gitignore` 대상이며 절대 커밋 금지. 열람·공유 금지.

## 하위 폴더 (별도 CLAUDE.md 불필요)

- `environments/` — 환경별 오버라이드. `development.rb`(리로딩 on, memory_store 캐시), `production.rb`(eager_load, `force_ssl`·`assume_ssl`, **`trusted_proxies` 명시**[kamal/도커 사설대역+루프백 — 로그인 IP 스로틀의 `request.remote_ip` 신뢰경계 감사가능화, 배포 시 실 CIDR 로 좁힘], `solid_cache_store`·`solid_queue` 어댑터, STDOUT 로깅), `test.rb`(리로딩 off, null_store, forgery 보호 off).
- `initializers/` — `assets.rb`(에셋 버전), `content_security_policy.rb`(전역 CSP — 리소스를 `:self` 로 제한, 인쇄 레이아웃 `onclick` 인라인 핸들러만 해시로 허용, 표지/OCR용 `img_src` https·blob 허용, script-src nonce), `filter_parameter_logging.rb`(로그에서 password·token 등 민감 파라미터 필터), `inflections.rb`(`monster_species` 를 불가산 처리해 라우트 헬퍼 정상화).
- `locales/` — `en.yml`(i18n 기본 로케일, 현재 샘플만). UI 한국어는 뷰/모델에 직접 기술.

## 패턴·규칙

- **다중 DB**: primary 외 cache/queue/cable 은 production 전용이며 각자 스키마·마이그레이션 경로가 분리됨(`db/CLAUDE.md` 참조).
- **비밀 관리**: 앱은 API 키를 `ENV["…"].presence || credentials.dig(…)`(ENV 우선, credentials 폴백)로 읽는다. **credentials 가 기본·권장 저장소**, ENV 는 운영자 대안 경로. Kamal 은 `RAILS_MASTER_KEY` 만 주입하고 API 키는 컨테이너가 credentials 에서 복호화해 읽는다. 코드/YAML 하드코딩 금지(`docs/API_KEYS.md` 참조).
- **CSP**: 새 외부 리소스(도메인·인라인 스크립트/스타일) 추가 시 `content_security_policy.rb` 를 반드시 갱신. 인쇄 레이아웃의 인라인 핸들러 텍스트를 바꾸면 sha256 해시도 재계산해야 함.
- **스코프형 기능 플래그 / kill switch(Phase 2b C3)**: 온디맨드 게임 콘텐츠 워밍은 `AppSetting.feature_enabled?("on_demand_games", scope:)` 로 제어한다(설정 값은 `app_settings` 의 `feature_flags` JSON, 관리자 `admin/settings`). 저장 규약 — `"on_demand_games"` 전역 값(**false=하드 kill: 스코프 무시·전부 오프라인**, 미설정=파일럿[기본 off, 스코프 on 만], true=확대[기본 on, 스코프 off 로 개별 격리]) + `"on_demand_games:classroom:<id>"`/`":school:<id>"` 스코프 오버라이드(학급 우선→학교). **한 학급 사고를 전교 off 없이 격리**하고 파일럿→확대 롤아웃을 가능케 한다(교사 검수 게이트 부활 아님, R4 준수). 기본 seeds 는 `on_demand_games => true`. rate limit/예산은 `RateLimiter`(Solid Cache 원자 increment)가 담당.

---
> ⚠️ **유지보수 규칙**: 이 폴더의 파일이 추가·삭제되거나 역할이 바뀌면 이 CLAUDE.md도 함께 갱신하세요. 특히 `routes.rb` 의 네임스페이스·리소스 변경, 다중 DB(`database.yml`) 구조 변경, CSP/시크릿 정책 변경은 즉시 반영하세요. 하위 폴더 구조가 바뀌면 관련 상·하위 CLAUDE.md 링크도 확인하세요.
