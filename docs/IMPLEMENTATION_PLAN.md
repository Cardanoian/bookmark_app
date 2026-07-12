# 「책갈피」 Rails 8 구현 계획서 (단계별 Step-by-Step)

> **목적**: [`docs/RAILS_PLAN.md`](./RAILS_PLAN.md)의 설계·제작 계획을 **착수 즉시 실행 가능한 단계별(Step-by-Step) 구현 계획**으로 확장한다. **Phase 0**(환경·스캐폴드 정합화)부터 시작해 **Phase 8**(배포)까지 각 단계를 번호가 매겨진 스텝으로 쪼개고, 스텝마다 **작업 / 대상 파일·명령 / 완료 정의(DoD)** 를 명시한다.
>
> 이 문서는 RAILS_PLAN.md(설계 확정)를 **대체하지 않고 실행 순서로 번역**한다. 스키마·역할·라우트의 근거는 항상 RAILS_PLAN 해당 섹션을 참조한다.
> 최종 수정: 2026-07-06

---

## 목차

- [0. 문서 사용법 · 범위](#0-문서-사용법--범위)
- [A. 현재 리포 상태 스냅샷 (실측)](#a-현재-리포-상태-스냅샷-실측)
- [B. Phase 의존성 그래프](#b-phase-의존성-그래프)
- [C. 공통 규약 (스텝·DoD·브랜치·커밋)](#c-공통-규약-스텝dod브랜치커밋)
- [Phase 0 — 개발 환경 · 스캐폴드 정합화 · 규약](#phase-0--개발-환경--스캐폴드-정합화--규약)
- [Phase 1 — 인증 · 역할 · 기반](#phase-1--인증--역할--기반)
- [Phase 2 — 핵심 도메인 (모델 · 대시보드)](#phase-2--핵심-도메인-모델--대시보드)
- [Phase 3 — 독후감 · AI 파이프라인 (핵심 가치)](#phase-3--독후감--ai-파이프라인-핵심-가치)
- [Phase 4 — 게이미피케이션 · 몬스터 도감](#phase-4--게이미피케이션--몬스터-도감)
- [Phase 5 — 콘텐츠 · 커뮤니티](#phase-5--콘텐츠--커뮤니티)
- [Phase 6 — 역할 도구 (교사 · 교무 · 사서)](#phase-6--역할-도구-교사--교무--사서)
- [Phase 7 — 총괄관리자 (superadmin)](#phase-7--총괄관리자-superadmin)
- [Phase 8 — 배포 (DigitalOcean · Kamal 2)](#phase-8--배포-digitalocean--kamal-2)
- [부록 A — RAILS_PLAN §16 체크리스트 ↔ 스텝 매핑](#부록-a--rails_plan-16-체크리스트--스텝-매핑)
- [부록 B — RAILS_PLAN §17 검증 계획 ↔ Phase 게이트 매핑](#부록-b--rails_plan-17-검증-계획--phase-게이트-매핑)
- [부록 C — 전역 위험 · 완화](#부록-c--전역-위험--완화)

---

## 0. 문서 사용법 · 범위

- **단위**: 각 Phase는 목표 → 전제(선행 Phase) → 산출물 → **스텝 목록** → **Phase 완료 게이트**로 구성한다.
- **스텝 ID**: `P{phase}.{n}` (예: `P0.3`). 스텝은 원칙적으로 위→아래 순서로 진행하되, "병렬" 표기가 있으면 동시에 진행 가능하다.
- **DoD(Definition of Done)**: 각 스텝의 "완료" 판정 기준. **증거(테스트 통과·명령 출력·화면 동작)** 로 확인한다. "될 것 같다"는 완료가 아니다.
- **범위 밖**: 실제 코드 구현·에셋(몬스터 이미지) 제작·API 키 발급은 이 문서의 범위가 아니다. 이 문서는 **무엇을 어떤 순서로 어떻게 검증하며** 만들지를 규정한다.
- **원문 대비 변경점**: RAILS_PLAN은 Phase 1에 스캐폴드를 포함했으나, **스캐폴드는 이미 완료**되었으므로(§A) 본 계획서는 이를 **Phase 0**으로 분리하고 정합화 작업을 추가한다. Phase 1~8의 의미는 RAILS_PLAN §16과 정렬하되 스텝을 세분화한다.

---

## A. 현재 리포 상태 스냅샷 (실측)

> 이 스냅샷은 계획을 현실에 고정한다. Phase 0는 이 격차(Δ)를 메우는 것으로 시작한다.

**이미 존재(완료)**
- Rails **8.1.3** 애플리케이션 스캐폴드(`rails new … -d sqlite3 -c tailwind` 상당).
- Ruby **4.0.5** (`.ruby-version`) — ⚠️ RAILS_PLAN §3은 "3.4"로 표기. **실제 4.0.5 기준으로 진행**하고 RAILS_PLAN 표기는 정보 격차로 간주.
- Gem: `propshaft`, `importmap-rails`, `turbo-rails`, `stimulus-rails`, `tailwindcss-rails`, `jbuilder`, `solid_cache`, `solid_queue`, `solid_cable`, `kamal`, `thruster`, `image_processing`, `bootsnap`, `brakeman`, `bundler-audit`, `rubocop-rails-omakase`, `debug`, `web-console`, `capybara`, `selenium-webdriver`.
- 인프라 파일: `Dockerfile`, `config/deploy.yml`, `.kamal/`, `config/database.yml`, `config/credentials.yml.enc`, `config/cable.yml`·`cache.yml`·`queue.yml`·`recurring.yml`, `.github/`(CI), `Procfile.dev`.
- Stimulus 스캐폴드: `app/javascript/controllers/{application,index,hello_controller}.js`.

**미착수(격차 Δ)**
- **Gem 누락**: `bcrypt`(현재 **주석 처리**), `pundit`, `faraday`. 테스트는 `cuprite` 대신 `selenium-webdriver` 사용 중.
- **도메인 전무**: `app/models`에 `application_record.rb`뿐, `db/migrate/` 비어 있음, `db/schema.rb` 없음, 커스텀 컨트롤러 없음, `config/routes.rb`는 기본(`root` 미설정).
- **참조 산출물 부재**: `prototype/`·`연구/` 디렉터리가 리포에 없음. `docs/`에 **RAILS_PLAN.md / monsters.md / 11_프로젝트_분석_보고서.md** 만 존재.
  - ⇒ `schools.js`(6,331교), `prototype/index.html` 프롬프트 원문 등 **원본 소스가 없음**. 시드 데이터는 **별도 확보(P0.7 리스크)** 필요.
- `docs/monsters.md`: 24라인×3단계=**72폼** 시드 + §7 기계판독 YAML **완성**. **Phase 1 시드 = 12라인(36폼)**.

**결정 필요(Phase 0에서 확정)**
- schools 시드 원본(`schools.js`) 확보 방법(원본 이관 / NEIS API 재수집 / 축소 시드).
- OCR·AI·도서·도서관 API 키 보유 여부(없으면 폴백 경로가 기본 동작이 됨).

---

## B. Phase 의존성 그래프

```
Phase 0 (환경·규약)
   │
   ▼
Phase 1 (인증·역할·Pundit·Current·schools 시드)
   │
   ▼
Phase 2 (핵심 모델: classrooms·users·reports·books + 대시보드 셸)
   │
   ├──────────────┬───────────────┐
   ▼              ▼               ▼
Phase 3        Phase 5         Phase 6
(독후감·AI)   (콘텐츠·커뮤니티)  (역할 도구: 교사·교무·사서)
   │              │               │
   ▼              │               │
Phase 4           │               │
(게이미피케이션)   │               │
   └──────────────┴───────────────┘
                  ▼
             Phase 7 (총괄관리자 — 전 도메인 CRUD·통계·모더레이션)
                  ▼
             Phase 8 (배포)
```

- **직렬 필수**: 0 → 1 → 2. 이후 3·5·6은 2 위에서 병렬 가능(팀 분업 시).
- **4는 3 의존**(포인트·등급·승인 이벤트가 진화/뱃지 트리거).
- **5는 2 의존(직접)이나, 게임 포인트 정합은 4에 소프트 의존**(Phase 5 게이트의 "게임 포인트↔게이미피케이션 정합"은 Phase 4 포인트 훅 스텁으로 선행 가능, 실연동은 4 이후).
- **7은 3~6의 도메인 모델 의존**(전역 CRUD·통계 대상이 존재해야 함).
- **8은 전 기능 안정 후**. 단, Phase 0에서 **배포 파이프라인 스모크(P0.9)** 는 미리 1회 검증.

---

## C. 공통 규약 (스텝·DoD·브랜치·커밋)

- **브랜치**: `phase-{n}/{slug}` (예: `phase-1/tuple-auth`). Phase 단위 PR 병합.
- **커밋**: 스텝 단위 원자 커밋. 메시지 첫 줄 `P{phase}.{n}: <요약>`.
- **테스트 우선순위**: 모델 유효성·인가(Pundit)·핵심 플로우(Capybara 시스템 테스트)는 **각 Phase 게이트의 필수 항목**.
- **명령 표기**: `bin/rails …`(스크립트 래퍼) 기준. 롱러닝(테스트·설치·빌드)은 백그라운드 실행.
- **품질 게이트(모든 Phase 공통, 병합 전 필수)**:
  1. `bin/rails test` + `bin/rails test:system` 그린
  2. `bin/rubocop` 무경고(omakase)
  3. `bin/brakeman` 신규 경고 0
  4. `bin/rails db:migrate` 후 `db:rollback` 왕복 무오류(마이그레이션 가역성)
  5. 해당 Phase의 **Pundit 경계 테스트** 통과(역할별 접근 차단 확인)

---

## Phase 0 — 개발 환경 · 스캐폴드 정합화 · 규약

**목표**: 이미 존재하는 Rails 8.1.3 스캐폴드를 RAILS_PLAN과 정합화하고, 이후 모든 Phase가 딛고 설 **gem·설정·규약·시드 전략·CI**의 토대를 확정한다.
**전제**: 없음(리포 존재).
**산출물**: 보강된 `Gemfile`/`Gemfile.lock`, `DESIGN.md`, credentials 스키마, 다중 DB 확인, 테스트/CI 그린, 시드 전략 결정 문서, 배포 스모크 1회.

- **P0.1 · 런타임·부팅 검증**
  - 작업: `ruby -v`(4.0.5), `bin/rails -v`(8.1.3) 확인. `bin/setup` 또는 `bundle install` 후 `bin/rails runner "puts Rails.env"` 부팅 확인.
  - DoD: 앱이 예외 없이 부팅, `/up` 헬스체크 200.

- **P0.2 · 누락 gem 보강** *(RAILS_PLAN §4)*
  - 작업: `Gemfile`에서 `gem "bcrypt", "~> 3.1.7"` **주석 해제**. `gem "pundit"`, `gem "faraday"` 추가. `:test` 그룹은 현행 `selenium-webdriver` 유지(결정: **Cuprite 도입은 선택**; 도입 시 `gem "cuprite"` 추가·드라이버 교체는 P3 시스템 테스트 도입 시점에 재검토). `bundle install`.
  - DoD: `bundle list | grep -E "bcrypt|pundit|faraday"` 3개 출력, 부팅 정상.

- **P0.3 · Tesseract/Daum 스크래퍼 부재 확인** *(RAILS_PLAN §4 주의)*
  - 작업: Gemfile에 `rtesseract`·`nokogiri` 기반 스크래핑 gem이 **없음**을 확인(있으면 제거). OCR은 Gemini만, 맞춤법은 `spelling` 축으로 대체.
  - DoD: `grep -Ei "tesseract|rtesseract" Gemfile` 무출력.

- **P0.4 · 다중 DB 구성 확인** *(RAILS_PLAN §14.2)*
  - 작업: `config/database.yml`의 `production`에 `primary/cache/queue/cable` 4개 DB와 각 `migrations_paths`가 있는지 확인. `db/cache_migrate`·`db/queue_migrate`·`db/cable_migrate` 존재 확인(Solid 설치 산출물).
  - DoD: `bin/rails db:prepare` 후 `storage/*.sqlite3`(dev 기준) 생성, `bin/rails runner "p ActiveRecord::Base.connection.adapter_name"` = SQLite.

- **P0.5 · Solid 어댑터 활성화 확인** *(RAILS_PLAN §3)*
  - 작업: `config/environments/production.rb`에서 `cache_store = :solid_cache_store`, `active_job.queue_adapter = :solid_queue`, `cable.yml` = `solid_cable` 확인. dev에서 잡 실행 경로 확인(`bin/jobs` 또는 `SOLID_QUEUE_IN_PUMA`).
  - DoD: 테스트 잡 1개를 enqueue→perform 확인(`bin/rails runner`로 간단 잡 실행).

- **P0.6 · credentials 스키마 정의** *(RAILS_PLAN §9.8, §15)*
  - 작업: `bin/rails credentials:edit`로 아래 키 **자리(placeholder)** 구조 생성. 값은 미보유 시 비워 두고 **폴백 경로가 기본 동작**임을 문서화.
    ```yaml
    gemini:       { api_key: "" }
    kakao:        { rest_key: "" }
    naver:        { client_id: "", client_secret: "" }
    data4library: { api_key: "" }
    ```
  - DoD: `Rails.application.credentials.gemini` 접근 가능. **API 키는 DB(app_settings) 저장 금지** 규약 명문화.

- **P0.7 · 시드 데이터 전략 확정(리스크 해소)** *(RAILS_PLAN §6.2 schools, §13)*
  - 작업: `schools.js`(6,331교) 원본이 리포에 **없음** → 다음 중 택1을 결정·기록: (a) 원본 파일 확보 후 `lib/tasks/schools.rake`로 변환, (b) NEIS 학교기본정보 OpenAPI로 재수집 rake, (c) 개발용 **축소 시드**(시도별 대표 N교)로 시작하고 프로덕션 시드는 후속. 도메인 상수(5축 루브릭·레벨·뱃지·게임·프롬프트)는 `config/`·`app/models/concerns` **Ruby 상수/시드**로 이식 위치 확정.
  - DoD: 선택안과 근거가 `progress`/PR 설명에 기록. 최소 **개발 시드 경로**가 존재.

- **P0.8 · 디자인 시스템 `DESIGN.md` + Tailwind 토큰** *(RAILS_PLAN §12)*
  - 작업: 리포 루트에 `DESIGN.md` 신규(컬러·타이포·스페이싱·컴포넌트 스펙: 카드/사이드바 콘솔/포디움/5축 방사형/**몬스터 도감·카드·진화 로드맵·케어 상점**/뱃지/진행바/상태·빈·에러 배너). Tailwind v4 `@theme`(또는 config)를 토큰과 1:1 매핑. Pretendard **self-host**(CDN 제거) 에셋 배치.
  - DoD: 토큰이 최소 1개 뷰에 적용되어 렌더, 명도대비 AA(≥4.5:1) 기준 명시. (⚠️ 이 스텝은 별도 산출물 — 토큰 값 자체는 DESIGN.md에서 확정)

- **P0.9 · 테스트·CI·정적분석 파이프라인 그린** *(RAILS_PLAN §15)*
  - 작업: `.github/`의 CI가 `rubocop`·`brakeman`·`bundler-audit`·`rails test`를 도는지 확인·보강. 로컬에서 4종 실행.
  - DoD: `bin/rails test` 그린, `bin/rubocop` 무경고, `bin/brakeman` 경고 0, CI가 PR에서 동일 게이트 수행.

- **P0.10 · 배포 파이프라인 스모크(사전 1회)** *(RAILS_PLAN §14)*
  - 작업: `config/deploy.yml`의 `service/image/servers/proxy/volumes/env` 구조를 §14.3과 대조. `.kamal/secrets`가 git에서 제외됨(`.gitignore`) 확인. **실배포는 Phase 8**이나, `kamal config`·`docker build`(로컬) 만 스모크.
  - DoD: `kamal version` 동작, Docker 이미지 로컬 빌드 성공(또는 Dockerfile lint), secrets 커밋 안 됨 확인.

**Phase 0 완료 게이트**
- [ ] P0.1~P0.10 DoD 충족, C절 품질 게이트(테스트/rubocop/brakeman) 그린
- [ ] 격차 Δ(누락 gem 3종) 해소, 시드 전략·API 키 보유 현황 문서화
- [ ] `DESIGN.md` 초안 존재, Tailwind 토큰 1:1 매핑 시작

---

## Phase 1 — 인증 · 역할 · 기반

**목표**: 튜플 신원(학교·학급·이름+비밀번호) 로그인, 5역할 체계, Pundit 인가 뼈대, `Current` 컨텍스트, schools 시드까지 — 모든 화면이 딛고 설 인증·인가 기반 완성.
**전제**: Phase 0.
**산출물**: `schools`·`users`(+최소 `classrooms`) 마이그레이션, SessionsController/RegistrationsController, ApplicationPolicy, `Current`, schools 시드.

- **P1.1 · `schools` 마이그레이션·모델·시드** *(RAILS_PLAN §6.2 schools)*
  - 작업: `bin/rails g model School neis_code:string:uniq name:string:index region:string gu:string office_code:string`. `lib/tasks/schools.rake`로 P0.7 선택안 시드 적재.
  - DoD: `School.count > 0`(개발 시드), `neis_code` unique·`name` 검색 인덱스 존재, `schools/search`가 아직 없어도 모델 쿼리 동작.

- **P1.2 · `role` enum + `users` 마이그레이션** *(RAILS_PLAN §6.2 users, §6.3, §7.1)*
  - 작업: `users` 생성 — `role:integer`(enum: student/teacher/school_admin/librarian/superadmin, default student, index), `school_id`(nullable=superadmin), `classroom_id`(nullable), `name`(not null), `password_digest`(not null), `points`(default 0), `mode`(enum normal/easy), `active_monster_id`(nullable), `suspended`(default false). 튜플 신원 인덱스 `[school_id, classroom_id, name]`.
  - DoD: `User` enum 5역할·mode 2값 정의, 마이그레이션 가역, 유니크 인덱스로 튜플 중복 차단(모델 테스트).

- **P1.3 · `classrooms` 최소 마이그레이션** *(RAILS_PLAN §6.2 classrooms)*
  - 작업: `classrooms` — `school_id`(FK,index), `grade`, `class_no`, `teacher_id`(FK users nullable,index), `rubric_config:json`, unique(`school_id,grade,class_no`). *(교사는 다학급 담임 가능 — teacher_id는 classroom 쪽에 둠.)*
  - DoD: unique 제약 테스트, `School has_many :classrooms`·`Classroom belongs_to :school` 연관 동작.

- **P1.4 · `has_secure_password` + 비밀번호 정책** *(RAILS_PLAN §15)*
  - 작업: `User`에 `has_secure_password`. 초기 발급/초기화도 **해시 저장**(평문 `1234` 금지). bcrypt 확인(P0.2).
  - DoD: `User.create(password: …)` 후 `authenticate` 성공/실패 테스트, `password_digest`가 평문 아님.

- **P1.5 · `Current` 컨텍스트** *(RAILS_PLAN §5 current.rb, §18)*
  - 작업: `app/models/current.rb`(`ActiveSupport::CurrentAttributes`) — `attribute :user, :classroom`. `ApplicationController`에서 세션 쿠키→`Current.user` 세팅 `before_action`.
  - DoD: 로그인 후 임의 컨트롤러에서 `Current.user` 참조 가능(요청 테스트).

- **P1.6 · SessionsController(튜플 신원 로그인)** *(RAILS_PLAN §8, §18)*
  - 작업: `resource :session, only: [:new,:create,:destroy]`. `new`는 학교→학급→이름→비밀번호 폼. `create`는 (school, classroom, name)로 User 조회 후 `authenticate`. 세션 쿠키 발급.
  - DoD: 정상 로그인→`root` 리다이렉트, 오자격 401/재표시(요청·시스템 테스트).

- **P1.7 · schools 검색 자동완성(JSON)** *(RAILS_PLAN §8 `schools/search`)*
  - 작업: `get "schools/search"` → `name LIKE` 상위 N개 JSON. 로그인 폼에서 debounce 자동완성(Stimulus `book_search_controller.js` 패턴 재사용 예정이나 여기선 최소 컨트롤러).
  - DoD: `GET /schools/search?q=…` JSON 응답, 인덱스 사용 확인.

- **P1.8 · RegistrationsController(학생·교사 셀프가입)** *(RAILS_PLAN §7.1 셀프가입 O)*
  - 작업: `resources :registrations, only: [:new,:create]`. 학생=학교·학급·이름·비번, 교사=학교·(담당학급 생성/선택)·이름·비번. `school_admin/librarian/superadmin`은 **셀프가입 불가**(발급/시드).
  - DoD: 학생/교사 가입 성공, 관리자 역할은 폼에서 선택 불가(정책·테스트).

- **P1.9 · Pundit 뼈대 + policy_scope** *(RAILS_PLAN §7.2)*
  - 작업: `ApplicationController`에 `include Pundit::Authorization`, `before_action :require_login`, `rescue_from Pundit::NotAuthorizedError → head :forbidden`. `ApplicationPolicy` 기본, `policy_scope` 뼈대.
  - DoD: 비로그인 접근 차단, `NotAuthorizedError`→403(요청 테스트).

- **P1.10 · superadmin 시드** *(RAILS_PLAN §7.1 superadmin=시드)*
  - 작업: `db/seeds.rb`에 superadmin 1계정(school_id NULL) 생성(초기 비번 해시).
  - DoD: 시드 후 superadmin 로그인 가능, `school_id` NULL.

**Phase 1 완료 게이트**
- [ ] 학생/교사 **가입→로그인→로그아웃** 시스템 테스트 그린
- [ ] 튜플 신원 유니크·학급 유일성 모델 테스트 통과
- [ ] 비로그인/오권한 접근 403, superadmin 시드 로그인 확인
- [ ] `bin/rails db:migrate`↔`db:rollback` 왕복 무오류

---

## Phase 2 — 핵심 도메인 (모델 · 대시보드)

**목표**: 독후감·도서를 포함한 핵심 관계형 모델을 완성하고, 5역할 각각의 **대시보드 셸 + Hotwire 네비**를 세워 이후 기능이 붙을 골격을 만든다.
**전제**: Phase 1.
**산출물**: `reports`·`books`(+`classrooms` 확장) 마이그레이션, 역할별 대시보드/레이아웃, Pundit 정책·스코프 확장.

- **P2.1 · `books` 마이그레이션·모델** *(RAILS_PLAN §6.2 books)*
  - 작업: `title(index)`, `author`, `publisher`, `isbn(index)`, `cover_url`, `grade_band`, `category`(enum recommended/classic/searched), `summary:text`. 44 권장도서+고전 시드 골격(값은 P5 확장).
  - DoD: enum 3값, `isbn` upsert(캐시) 가능한 유니크/인덱스 확인.

- **P2.2 · `reports` 마이그레이션·모델(최대 레코드)** *(RAILS_PLAN §6.2 reports)*
  - 작업: `user_id`·`classroom_id`·`book_id`(nullable)·`book_title`·`body:text`·`input_mode`(enum keyboard/wongoji/ocr)·`rubric:json`·`avg:real`·`level:string(1) index`·`teacher_rubric:json`·`teacher_comment:text`·`reviewed:bool index`·`reviewed_at`·`shared:bool`·`cheers_count:int`·`challenge_id`·`mission_id`·`revision_of`(FK reports)·`prev_avg`·`improvement`·`similarity`·`ai_status`(enum pending/processing/done/failed). 인덱스 `[classroom_id, reviewed]`·`[user_id, created_at]`.
  - DoD: enum 3종 정의, 자기참조(`revision_of`) 동작, 인덱스 존재, 모델 유효성 테스트.

- **P2.3 · Active Storage 첨부 선언** *(RAILS_PLAN §6.2, §5)*
  - 작업: `bin/rails active_storage:install && db:migrate`(스캐폴드에 포함 여부 확인 후). `Report`에 `has_one_attached :photo, :drawing, :audio`. content_type·용량 검증(§15).
  - DoD: 첨부 저장·조회 테스트, 크기/타입 검증 실패 케이스 테스트.

- **P2.4 · `classrooms.rubric_config` 규약 확정** *(RAILS_PLAN §6.2)*
  - 작업: `rubric_config` JSON 형태 확정 `{weights:{content,emotion,life,structure,spelling}, emphasis, label}`. 기본값 시드(§13.1 5축).
  - DoD: 신규 classroom 생성 시 기본 가중치 주입, 파싱 헬퍼 테스트.

- **P2.5 · 연관·`policy_scope` 확장** *(RAILS_PLAN §7.2)*
  - 작업: `User has_many :reports`, `Classroom has_many :reports/:users`, `Book has_many :reports`. `ReportPolicy::Scope`(교사=자기 학급, 학생=본인), `ClassroomPolicy`(학교 경계).
  - DoD: 교사는 자기 학급 reports만 조회(스코프 테스트), 타 학급 접근 차단.

- **P2.6 · `dashboard#show` 역할 분기 라우팅** *(RAILS_PLAN §8 root)*
  - 작업: `root "dashboard#show"`. 로그인·역할에 따라 student/teacher/school_admin/librarian/superadmin 대시보드로 분기(리다이렉트 또는 역할별 렌더).
  - DoD: 5역할 각각 로그인 후 올바른 대시보드 진입(시스템 테스트 5케이스).

- **P2.7 · 역할별 레이아웃·Hotwire 네비 셸** *(RAILS_PLAN §5 views, §11)*
  - 작업: 역할별 레이아웃/사이드바(교사=콘솔형, 학생=탭형) 뼈대, Turbo Drive 네비, DESIGN.md 토큰 적용. 빈 상태 컴포넌트.
  - DoD: 각 역할 네비가 Turbo로 이동, 레이아웃 렌더(스냅샷/시스템 테스트).

- **P2.8 · Pundit 경계 회귀 테스트 세트** *(RAILS_PLAN §17 인가 경계)*
  - 작업: 학생/교사/교무/사서/총괄 5역할 × 대표 리소스 접근 매트릭스 테스트 작성.
  - DoD: 경계 위반 전부 403, 정상 접근 통과(매트릭스 그린).

**Phase 2 완료 게이트**
- [ ] `schools/classrooms/users/reports/books` 스키마가 RAILS_PLAN §6과 컬럼 단위 정합
- [ ] 5역할 대시보드 진입 + Turbo 네비 동작
- [ ] `policy_scope` 목록 자동 필터 + 경계 매트릭스 테스트 그린
- [ ] 마이그레이션 가역성·품질 게이트(C절) 그린

---

## Phase 3 — 독후감 · AI 파이프라인 (핵심 가치)

**목표**: 3입력 모드 작성 → (선택)OCR → AI 5축 첨삭(폴백 포함) → 교사 검토·조정·승인 → 실시간 반영까지, 앱의 **Must-Keep 핵심 가치**(§1.3) 파이프라인을 완성한다.
**전제**: Phase 2.
**산출물**: `Ai::*` 서비스·잡, 5축 루브릭 concern, 교사 리뷰 UI + Turbo Stream, 고쳐쓰기·진위.

- **P3.1 · 독후감 CRUD + 3입력 모드 골격** *(RAILS_PLAN §8, §13.3 위저드)*
  - 작업: `resources :reports do member{post :revise; post :share}`. 작성 폼에 `input_mode` 3택: 키보드 / 원고지 / 사진OCR. `ReportPolicy`(create=학생 본인, update=작성자|담임).
  - DoD: 학생 독후감 생성·수정·조회, 정책 차단 테스트.

- **P3.2 · 원고지 Stimulus 컨트롤러** *(RAILS_PLAN §5, §11 wongoji)*
  - 작업: `app/javascript/controllers/wongoji_controller.js` — 200칸 그리드 입력, `body`와 동기화.
  - DoD: 원고지 입력이 `report.body`로 저장(시스템 테스트).

- **P3.3 · `Ai::GeminiClient`** *(RAILS_PLAN §9.2)*
  - 작업: `app/services/ai/gemini_client.rb` — `gemini-2.5-flash:generateContent` 래퍼(Faraday), `responseMimeType: application/json`, 키=`credentials.gemini.api_key`. 키 없음/실패 시 예외로 폴백 신호.
  - DoD: 목(mock) 응답 파싱 테스트, 키 없음 시 명확한 폴백 분기.

- **P3.4 · 사진 업로드 + `Ai::OcrService` + `OcrJob`** *(RAILS_PLAN §9.3)*
  - 작업: `resource :ocr, only: [:create]` → 이미지 Active Storage 저장 → `OcrJob` → `Ai::OcrService`(base64 inlineData + OCR_PROMPT, temp 0.1) → `report.update(body:, ai_status: :done)` → **Turbo Stream**으로 에디터 갱신. `photo_upload_controller.js`(Canvas 압축·미리보기).
  - DoD: 사진→텍스트 초안이 에디터에 비동기 반영(잡 테스트+시스템 테스트, 서비스는 mock).

- **P3.5 · OCR 키 없음 → 사진모드 비활성** *(RAILS_PLAN §9.3, §17 폴백)*
  - 작업: `credentials.gemini.api_key` 미설정 시 사진(OCR) 입력 모드 **비활성** + "키보드/원고지로 입력해 주세요" 안내. **Tesseract 폴백 없음**(확정).
  - DoD: 키 없는 환경에서 사진모드 숨김/차단, 키보드·원고지 정상(시스템 테스트).

- **P3.6 · `Ai::ReviewService` + `Ai::RuleBasedReview` 폴백 + `AiReviewJob`** *(RAILS_PLAN §9.4)*
  - 작업: 제출→`AiReviewJob`→`Ai::ReviewService`(본문+책+RUBRIC_PROMPT)→JSON 검증 `{level, rubric{5축}, praise[], fix[], grow[{text,standard_code}], pts}` 저장. 키 없음/실패→`Ai::RuleBasedReview`(키워드·길이·구조 휴리스틱). **AI 첨삭 폴백은 유지**.
  - DoD: 키 있음=LLM 경로, 키 없음=규칙기반 **무중단** 채점(§17 폴백 테스트), `ai_status` 전이 pending→processing→done/failed.

- **P3.7 · `RubricScorable` concern (A/B/C·포인트)** *(RAILS_PLAN §5 concerns, §13.1)*
  - 작업: `app/models/concerns/rubric_scorable.rb` — 5축 평균→A/B/C 판정(삶 연관·성찰 가중), 포인트 A30/B20/C10 산출, `avg`·`level` 저장.
  - DoD: 대표 입력에 대한 등급·포인트 결정 테스트(경계값 포함).

- **P3.8 · 교사 검토 큐 + 5축 조정·코멘트·승인** *(RAILS_PLAN §8 teacher/reviews, §10)*
  - 작업: `namespace :teacher { resources :reviews do member{post :approve; post :verify}; collection{post :batch_approve} }`. 검토 화면에서 `teacher_rubric` ±조정·`teacher_comment`·승인. 정책=학급 담임.
  - DoD: 담임만 검토/승인(정책 테스트), 승인 시 `reviewed=true`·`reviewed_at` 기록.

- **P3.9 · Turbo Stream 실시간(제출→검토 큐, 승인→학생)** *(RAILS_PLAN §10)*
  - 작업: `Report broadcasts_to ->(r){[r.classroom, :review_queue]}`. AI 첨삭 완료 잡 콜백에서 `broadcast_append_to [classroom, :review_queue]`. 승인 시 `broadcast_replace_to [user, :reports]`. Solid Cable.
  - DoD: **2세션(교사·학생)** 시스템 테스트 — 제출 시 교사 큐 즉시 추가, 승인 시 학생 화면 즉시 갱신(§17 실시간).

- **P3.10 · 고쳐쓰기(revise)·향상도** *(RAILS_PLAN §6.2 revision_of/improvement)*
  - 작업: `revise`가 `revision_of` 연결·`prev_avg` 기록, 재채점 후 `improvement` 산출. 고쳐쓰기 diff 표시.
  - DoD: 원본 대비 향상도 계산·표시 테스트.

- **P3.11 · `Ai::VerifyService`·유사도** *(RAILS_PLAN §9.5)*
  - 작업: `verify`(진위·표절 VERIFY_PROMPT) 교사 보조. `report.similarity`=학급 내 최대 유사도(Ruby 계산).
  - DoD: 유사도 산출·표시, 진위 보조 결과 교사 화면 노출(서비스 mock 테스트).

- **P3.12 · 중간 검사(맞춤법 축소)** *(RAILS_PLAN §16 Phase3, §13.1 spelling)*
  - 작업: Daum 스크래퍼 없이 `spelling` 축/규칙 사전으로 맞춤법 신호 축소 제공.
  - DoD: 맞춤법 피드백이 `spelling` 축으로 통합되어 표시.

**Phase 3 완료 게이트**
- [ ] **학생 작성→(OCR/AI 첨삭)→교사 승인→포인트 반영** end-to-end 시스템 테스트 그린(§17 핵심 플로우)
- [ ] 키 없는 폴백: AI 첨삭 규칙기반 무중단 + 사진 OCR 비활성 안내 + 키보드·원고지 정상
- [ ] 실시간(Turbo Stream) 2세션 반영 확인
- [ ] `ai_status` 상태기계·향상도·유사도 테스트 통과

---

## Phase 4 — 게이미피케이션 · 몬스터 도감

**목표**: 포인트·트레이너 레벨, **반려 몬스터 도감/진화**(아바타 대체), 뱃지, 3단 랭킹·명예의 전당, 미션·챌린지로 지속 독서 동기 장치를 완성한다.
**전제**: Phase 3(포인트·등급·승인 이벤트가 트리거).
**산출물**: `Pointable`/`Leveling`/`Evolvable`/`Badgeable` concern, `monster_species`/`user_monsters` + `docs/monsters.md` 시드, 상점, 랭킹.

- **P4.1 · `Pointable`·`Leveling` + 트레이너 칭호** *(RAILS_PLAN §13.2)*
  - 작업: `app/models/concerns/{pointable,leveling}.rb` — 포인트 적립, LEVEL_PATH(0/100/250/450/700/1000) 임계→레벨·칭호. 헤더에 `broadcast_update_to [user, :points]`.
  - DoD: 포인트 적립→레벨업 경계 테스트, 헤더 실시간 갱신.

- **P4.2 · `monster_species` 마이그레이션·모델** *(RAILS_PLAN §6.2 monster_species, §6.3)*
  - 작업: `dex_no:index`, `stage:int`, `key:string:uniq`, `name`, `element:int`(enum 6종), `rarity:int`(enum common/rare/epic), `evolves_from_id`(self FK nullable,index), `evolve_condition:json`, `image_key`, `description:text`.
  - DoD: enum·자기참조 진화체인 동작, unique key.

- **P4.3 · `user_monsters` 마이그레이션·모델** *(RAILS_PLAN §6.2 user_monsters)*
  - 작업: `user_id:index`, `dex_no:index`, `monster_species_id`(현재 폼), `nickname`(nullable), `obtained_at`, `evolved_at`(nullable), `care:json`, unique(`user_id, dex_no`). `users.active_monster_id` 연결.
  - DoD: 라인당 1개(제자리 진화) 유니크 테스트, 도감 완성도=보유 dex_no/**전체 설계 라인 수(24, 시드된 12가 아님)** 계산 — dex_half/dex_complete 뱃지 분모 기준(§6.3 monsters.md).

- **P4.4 · 몬스터 시드(Phase 1 = 12라인×3 = 36폼)** *(docs/monsters.md §6.2, §7 YAML)*
  - 작업: `docs/monsters.md §7` 기계판독 YAML을 `db/seeds.rb`(또는 rake)로 적재. Phase 1 시드 = 12라인(스타터 3 + 해금후보 3 포함). `evolves_from` 체인·`evolve_condition` 원본 그대로.
  - DoD: 시드 후 `MonsterSpecies.count == 36`, 각 라인 stage 1·2·3, `evolve_condition`이 monsters.md와 일치(정합 스크립트).

- **P4.5 · 획득 규칙(스타터 선택 + 마일스톤 발견)** *(RAILS_PLAN §13.5, monsters.md §6.1)*
  - 작업: 첫 로그인/온보딩 시 **스타터 3종 중 선택**. 레벨업·챌린지·뱃지·카테고리 최초 달성 등 **마일스톤마다 신규 발견**(알 부화 연출). **가챠·유료 없음**.
  - DoD: 스타터 선택 저장, 마일스톤 트리거로 신규 `user_monster` 생성(테스트). 랜덤 뽑기 경로 부재 확인.

- **P4.6 · `Evolvable` 진화 엔진(포인트 + 독서행동 조건)** *(RAILS_PLAN §13.5, monsters.md §4·§5)*
  - 작업: `app/models/concerns/evolvable.rb` — report 승인·포인트 지급·뱃지 획득 시점 후크로 `evolve_condition` 평가(포인트 임계 + distinct_genres/a_grades/classics/streak_days/badge 등). 충족 시 "진화 가능!" 표시→학생 실행(또는 자동), `monster_species_id` 갱신·`evolved_at`.
  - DoD: 대표 라인(이야기/지식/감성 등) 조건 충족·미충족 판정 테스트, 진화 시 폼 교체.

- **P4.7 · 진화·발견 연출(Turbo Stream)** *(RAILS_PLAN §10)*
  - 작업: `broadcast_replace_to [user, :active_monster]`. `monster_care_controller.js`(먹이·진화 연출), `dex_controller.js`(필터·상세).
  - DoD: 진화/신규 발견 시 헤더·도감 즉시 갱신(시스템 테스트).

- **P4.8 · 케어/진화 아이템 상점(shop_items/purchases 피벗)** *(RAILS_PLAN §6.2 shop_items/purchases, §13.5)*
  - 작업: `shop_items`(enum food/evolution_stone/care/decoration/accessory, cost, effect:json, consumable), `purchases`(quantity, 소모품 재고 / 영구 장식 unique). `resource :shop; resources :purchases`. 포인트 sink.
  - DoD: 구매→포인트 차감·재고 증가/영구 unique, 먹이/돌로 진화 조건 가속 반영.

- **P4.9 · 뱃지 13종 + 트리거** *(RAILS_PLAN §13.3, monsters.md §6.3)*
  - 작업: `badges`(key unique 13종: first/three/ten/levelA/tripleA/reviser/grower/challenger/ocr/first_evolve/dex_half/dex_complete/final_form)·`user_badges`(unique user+badge). `Badgeable` concern 획득 트리거. **dex_half/dex_complete 분모는 24 설계 라인 기준**(monsters.md §6.3: 12/24·24/24) — Phase 1에서 12라인만 시드되어도 12/12로 조기 발부되지 않도록 분모를 24로 고정.
  - DoD: 조건 충족 시 뱃지 부여(중복 금지) 테스트, 진화·도감 뱃지 트리거 연동, dex_complete가 12라인 시드에서 조기 발부되지 않음(경계 테스트).

- **P4.10 · 3단 랭킹 + 포디움 + 명예의 전당** *(RAILS_PLAN §8 rankings, §13.5)*
  - 작업: `resources :rankings`(class/school/nation/challenge/hall). **성장 기반** 신호=도감 완성도+진화 성취(완전형 수). `podium_component`·`evolution_roadmap_component`. `broadcast_replace_to [classroom, :ranking]`.
  - DoD: 3단 랭킹 산출·포디움 렌더, 명예의 전당이 도감·진화 반영(테스트).

- **P4.11 · 미션·챌린지·시즌** *(RAILS_PLAN §6.2 missions/challenges/seasons)*
  - 작업: `missions`(classroom), `challenges`(scope global/school), `seasons`. 참여→포인트·뱃지·진화 조건 연동.
  - DoD: 미션 참여가 진화/뱃지 조건에 반영(통합 테스트).

**Phase 4 완료 게이트**
- [ ] 몬스터 시드 36폼 정합(monsters.md와 evolve_condition 일치)
- [ ] 스타터 선택·마일스톤 발견·진화 엔진(포인트+독서행동) 판정 테스트 그린
- [ ] 뱃지 13종 트리거·3단 랭킹·명예의 전당(도감·진화 반영) 동작
- [ ] 가챠/유료 요소 부재 확인(대회 공정성·사행성 방지)

---

## Phase 5 — 콘텐츠 · 커뮤니티

**목표**: 도서 카탈로그·검색, 우수작 게시판·토론, 단계 학습 위저드, 독서게임 10종을 붙인다.
**전제**: Phase 2(모델). 게임·위저드는 Phase 3·4 지표와 연동.
**산출물**: `Books::SearchService`, 게시판/토론, 위저드, 게임 10종(증분).

- **P5.1 · `Books::SearchService`(Kakao→Naver 폴백)** *(RAILS_PLAN §9.6)*
  - 작업: `app/services/books/search_service.rb` — Kakao 실패→Naver, 정규화 `{title,author,publisher,thumbnail,isbn,description}`, 결과 `books`에 `category: searched` upsert 캐시. `resources :books do collection{get :search} end`. `book_search_controller.js`(debounce).
  - DoD: 검색 자동완성·표지, 키 없음/실패 시 graceful 폴백(§17), 캐시 upsert.

- **P5.2 · 도서 카탈로그 시드(44 권장+고전)** *(RAILS_PLAN §6.2 books, §13.3)*
  - 작업: 권장 44 + 고전 시드 데이터 적재, `book_card_component`.
  - DoD: 카탈로그 목록·상세 렌더, 카테고리 필터.

- **P5.3 · 우수작 게시판(board_posts/cheers/stickers)** *(RAILS_PLAN §6.2, §8)*
  - 작업: `board_posts`(report_id unique, hidden, hidden_by), `cheers`(unique post+user), `stickers`(position, emoji, label, by_user). `resources :board_posts do resources :cheers; resources :stickers end`. 응원/스티커 Turbo Stream.
  - DoD: 공유(`report.shared`)→게시, 응원 1인 1회·`cheers_count` 카운터캐시, 스티커 동료평가.

- **P5.4 · 토론방(topics/forum_posts)** *(RAILS_PLAN §6.2, §8)*
  - 작업: `topics`(scope classroom/school, hidden), `forum_posts`(likes_count, hidden). `resources :topics do resources :forum_posts end`.
  - DoD: 토픽 생성·글 작성·좋아요, 스코프 경계(학급/학교) 정책.

- **P5.5 · 단계 학습 위저드(5단계)** *(RAILS_PLAN §13.3, §8 learn)*
  - 작업: `resources :learn, only: [:index]` — 책 고르기→줄거리→인상장면→생각·느낌→삶과 연결(성취기준 코드 주입). 위저드 결과가 독후감 초안으로.
  - DoD: 5단계 진행·이탈 복귀, 결과가 report 작성으로 연결(시스템 테스트).

- **P5.6 · 독서게임 5종** *(RAILS_PLAN §8 games, §13.3)*
  - 작업: `namespace :games`(quiz/classic/vocab/whoami + book). quiz·classic=mcq, vocab=매칭, whoami=힌트 순차공개는 학생 온디맨드 출제(교사 검수 게이트 없이 즉석), book(책 소개 대결)은 소셜 도메인. `quizzes/quiz_questions/quiz_attempts` 연동(포인트 반영).
  - DoD: 각 게임 플레이→`quiz_attempts`/포인트 반영, quiz·vocab·whoami·book 통합 테스트 그린.

**Phase 5 완료 게이트**
- [ ] 도서 검색(키 있음 실제/키 없음 폴백)·카탈로그·표지 동작
- [ ] 게시판(응원·스티커)·토론(스코프 경계) 정책 테스트 그린
- [ ] 위저드 5단계→독후감 연결, 게임 10종 라우트 + 핵심 3종 동작
- [ ] 게임 포인트가 게이미피케이션(Phase 4)과 정합

---

## Phase 6 — 역할 도구 (교사 · 교무 · 사서)

**목표**: 교사·교무관리자·사서 전용 도구(통계·문서 출력·외부 연동)를 완성한다.
**전제**: Phase 3(교사 검토), Phase 2(모델).
**산출물**: 교사 CSV/PDF·인사이트, 교무 NEIS 요약, 사서 대시보드+정보나루/CSV.

- **P6.1 · 교사 대시보드·5축 인사이트** *(RAILS_PLAN §16 Phase6, §8 teacher)*
  - 작업: `teacher/dashboard` — 학급 5축 평균·향상도·검토 큐 요약, `radar_chart_component`(5축 방사형 SVG, 서버 렌더).
  - DoD: 학급 통계 렌더, 방사형 컴포넌트 정확 표시.

- **P6.2 · 교사 학생 관리·미션·퀴즈·루브릭** *(RAILS_PLAN §8 teacher)*
  - 작업: `teacher/students`(reset_password/give_points), `teacher/missions`·`quizzes`, `teacher/rubric_config`(edit/update).
  - DoD: 학생 관리·포인트 지급·루브릭 가중치 수정 반영(정책=담임).

- **P6.3 · 교사 문서 출력(CSV·PDF)** *(RAILS_PLAN §16 Phase6, §17 대회요건)*
  - 작업: CSV 내보내기(사전·사후 5축 비교용), print CSS + 전용 레이아웃으로 표창장/가정통신문/포트폴리오/성장리포트, 성장카드 PNG(`growth_card_controller.js` Canvas).
  - DoD: CSV 원자료 다운로드(§17 대회요건), print 레이아웃 출력, 성장카드 PNG 생성.

- **P6.4 · 교무관리자 전교 통계 + NEIS 생기부 요약** *(RAILS_PLAN §8 school_admin)*
  - 작업: `school_admin/stats`(전교 참여율·5축 평균), `school_admin/neis`(생기부 자동요약·복사).
  - DoD: 학교 범위 통계(정책=자기 학교), NEIS 요약 텍스트 생성·복사.

- **P6.5 · 사서 대시보드 + `Library::Data4libraryService` + CSV** *(RAILS_PLAN §9.7, §8 librarian)*
  - 작업: `librarian/dashboard`·`events`·`loans`(sync_data4library/import_csv). `library_loans` upsert(정보나루 or CSV). 이달의 책·행사.
  - DoD: 정보나루 키 있음=실제 집계/없음=CSV 폴백, 인기대출 표시(§17 외부 연동).

**Phase 6 완료 게이트**
- [ ] 교사 CSV(사전·사후 비교) + PDF 출력물 동작(§17 대회요건)
- [ ] 교무 전교 통계·NEIS 요약(자기 학교 경계) 정책 테스트
- [ ] 사서 정보나루 동기화/CSV 업로드 폴백 동작
- [ ] 역할 경계(교사≠교무≠사서) Pundit 테스트 그린

---

## Phase 7 — 총괄관리자 (superadmin)

**목표**: `/admin` 전역 네임스페이스에서 학교·사용자·전역 콘텐츠·시스템 설정·전교 통합 통계·모더레이션을 관리한다. school_admin(교무)과 **코드·정책상 명확히 격리**.
**전제**: Phase 3~6 도메인 모델(CRUD·통계·모더레이션 대상 존재).
**산출물**: `admin/*` 컨트롤러·정책, 전역 콘텐츠 CRUD(몬스터 도감 포함), `app_settings`, 통합 통계, 모더레이션.

- **P7.1 · `/admin` 네임스페이스 + 정책 격리** *(RAILS_PLAN §7.3, §8 admin)*
  - 작업: `namespace :admin { root "analytics#show" … }`. `Admin::*Policy`는 `superadmin`만 통과, `before_action`에서 `authorize [:admin, record]`. school_admin 접근 차단.
  - DoD: superadmin만 `/admin` 진입(정책 테스트), school_admin 403.

- **P7.2 · 학교·사용자 관리** *(RAILS_PLAN §7.3-1)*
  - 작업: `admin/schools`(등록/승인), `admin/users`(suspend/reset_password/role 변경, 검색). 학급 생성/이동.
  - DoD: 계정 정지(`suspended`)·역할 부여·비번 초기화(해시)·학교 승인 동작.

- **P7.3 · 전역 콘텐츠 CRUD(몬스터 도감 포함)** *(RAILS_PLAN §7.3-2, §8)*
  - 작업: `admin/books`·`quizzes`·`badges`·`shop_items`·`monster_species`(진화 규칙 포함) CRUD.
  - DoD: 전역 도서/퀴즈/뱃지/상점/**몬스터 종·진화 규칙** 편집 반영, 진화체인 무결성 검증.

- **P7.4 · 시스템 설정(`app_settings`)** *(RAILS_PLAN §6.2 app_settings, §7.3-3)*
  - 작업: `admin/settings`(feature_flags·default_rubric_weights·seasonal_banner·데모 시드 재생성). **API 키는 저장 금지**(credentials/ENV).
  - DoD: 기능 플래그 토글이 앱 동작에 반영, app_settings에 키 저장 시도 차단(테스트).

- **P7.5 · 전교 통합 통계 + CSV** *(RAILS_PLAN §7.3-4)*
  - 작업: `admin/analytics`(전 학교 참여율·5축·전국 랭킹 원자료) + `export`(전교 CSV).
  - DoD: 전역 통계 렌더, CSV 내보내기 다운로드.

- **P7.6 · 모더레이션** *(RAILS_PLAN §7.3-5, §6.2)*
  - 작업: `admin/moderation`(board_posts/forum_posts hide/unhide, 신고 처리). `hidden`·`hidden_by`.
  - DoD: 숨김/해제 반영, 숨김 콘텐츠 학생 화면 비노출(테스트).

**Phase 7 완료 게이트**
- [ ] `/admin`이 superadmin 전용(school_admin·기타 역할 전부 403) — §17 인가 경계
- [ ] 전역 콘텐츠(몬스터 도감 포함) CRUD·진화체인 무결성
- [ ] app_settings 기능 플래그 반영 + API 키 저장 금지 보장
- [ ] 전교 통합 통계·CSV·모더레이션 동작

---

## Phase 8 — 배포 (DigitalOcean · Kamal 2)

**목표**: 퍼시스턴트 볼륨 기반 SQLite로 DigitalOcean 드로플릿에 배포하고, SSL·시드·폴백 데모까지 스모크 검증한다.
**전제**: Phase 1~7 안정(품질 게이트 통과). Phase 0.10에서 파이프라인 스모크 선행.
**산출물**: 실서비스 배포, 볼륨 영속성·SSL·시드 검증.

- **P8.1 · Dockerfile·`deploy.yml`·볼륨·secrets 확정** *(RAILS_PLAN §14.1~14.3)*
  - 작업: `config/deploy.yml`에 `service/image/servers.web/proxy.ssl+host/volumes(chaekgalpi_storage:/rails/storage)/env.clear(RAILS_ENV, SOLID_QUEUE_IN_PUMA:true)/env.secret(RAILS_MASTER_KEY, *_API_KEY 등)` 확정. `.kamal/secrets`로 주입(git 금지).
  - DoD: `kamal config` 검증 통과, secrets 커밋 안 됨.

- **P8.2 · 드로플릿·볼륨·프록시 준비** *(RAILS_PLAN §14.1)*
  - 작업: Ubuntu 24.04 2GB+ 드로플릿, Docker, 퍼시스턴트 볼륨(`/rails/storage`=SQLite primary+queue/cache/cable + Active Storage), kamal-proxy(Let's Encrypt).
  - DoD: 볼륨 마운트 확인, 도메인·SSL 발급.

- **P8.3 · 최초 배포 + DB 준비·시드** *(RAILS_PLAN §14.4)*
  - 작업: `kamal setup`(최초) → `kamal deploy`. `kamal app exec "bin/rails db:prepare"` → `kamal app exec "bin/rails db:seed"`(schools + 데모 + 도메인 상수 + 몬스터 시드).
  - DoD: 앱 기동, `/up` 200, 시드 데이터 조회 가능.

- **P8.4 · 스모크 · 폴백 데모 검증** *(RAILS_PLAN §17)*
  - 작업: 핵심 플로우(작성→첨삭→승인→포인트) 스모크, 키 없는 폴백 데모(AI 규칙기반·사진OCR 비활성), 실시간 2세션, 재배포 후 볼륨 데이터 유지·SSL 확인.
  - DoD: §17 검증 표의 각 항목 그린(핵심 플로우/실시간/폴백/외부연동/인가/영속성/무결성/대회요건).

**Phase 8 완료 게이트**
- [ ] 재배포 후에도 볼륨 데이터·SSL 유지(영속성)
- [ ] 폴백 데모(키 없음) 무중단 동작
- [ ] §17 검증 계획 전 항목 통과(부록 B)

---

## 부록 A — RAILS_PLAN §16 체크리스트 ↔ 스텝 매핑

> 원문 §16의 모든 항목이 본 계획서 스텝으로 커버됨을 보증(누락 0).

| RAILS_PLAN §16 항목 | 대응 스텝 |
|------|------|
| **Phase 1** `rails new` + Solid 설치·마이그레이션 | P0.1, P0.4, P0.5 (스캐폴드 완료·정합) |
| Gemfile 확정·bundle·importmap/turbo/stimulus 확인 | P0.2, P0.3 |
| DESIGN.md + Tailwind 토큰·Pretendard self-host | P0.8 |
| Pundit·Active Storage 셋업, Current | P1.9, P2.3, P1.5 |
| 인증(튜플 신원)·has_secure_password | P1.4, P1.6 |
| role enum(superadmin) | P1.2 |
| schools.rake 시드(6,331) | P0.7, P1.1 |
| **Phase 2** schools/classrooms/users/reports/books 마이그레이션 | P1.1, P1.3, P1.2, P2.2, P2.1 |
| 가입·로그인·학교검색 자동완성 | P1.8, P1.6, P1.7 |
| 역할별 대시보드 셸 + Hotwire 네비 | P2.6, P2.7 |
| Pundit 정책 뼈대 + policy_scope | P1.9, P2.5, P2.8 |
| **Phase 3** 3입력 모드(키보드/원고지/사진OCR) | P3.1, P3.2, P3.4 |
| Active Storage(photo/drawing/audio) | P2.3 |
| GeminiClient + OcrService/OcrJob + 키없음 비활성 | P3.3, P3.4, P3.5 |
| ReviewService + RuleBasedReview + AiReviewJob | P3.6 |
| 5축 루브릭 산출(RubricScorable, A/B/C·포인트) | P3.7 |
| 교사 검토·조정·코멘트·승인 + Turbo Stream | P3.8, P3.9 |
| 고쳐쓰기 diff·향상도, 진위·유사도 | P3.10, P3.11 |
| 중간 검사(맞춤법 축소) | P3.12 |
| **Phase 4** 포인트/트레이너 레벨 + 칭호 | P4.1 |
| 반려 몬스터 도감 마이그레이션+시드(12라인×3) | P4.2, P4.3, P4.4 |
| 몬스터 획득 + 진화 엔진 + 연출 | P4.5, P4.6, P4.7 |
| 케어/진화 아이템 상점 + 컴포넌트 | P4.8 |
| 뱃지 13종 + 트리거 | P4.9 |
| 3단 랭킹 + 포디움 + 명예의 전당 | P4.10 |
| 미션·챌린지·시즌 | P4.11 |
| **Phase 5** 도서 카탈로그 + SearchService | P5.1, P5.2 |
| 게시판(cheers/stickers) + 토론(topics/forum) | P5.3, P5.4 |
| 단계 학습 위저드(5단계) | P5.5 |
| 독서게임 10종(증분) | P5.6 |
| **Phase 6** 교사 대시보드·인사이트·CSV·PDF | P6.1, P6.2, P6.3 |
| 교무 전교 통계 + NEIS 요약 | P6.4 |
| 사서 대시보드 + Data4library + CSV | P6.5 |
| **Phase 7** /admin 네임스페이스 + 정책 격리 | P7.1 |
| 학교·사용자 관리 | P7.2 |
| 전역 콘텐츠(몬스터 도감 포함) | P7.3 |
| 시스템 설정(app_settings) | P7.4 |
| 전교 통합 통계 + CSV | P7.5 |
| 모더레이션 | P7.6 |
| **Phase 8** Dockerfile/deploy.yml + 볼륨 + secrets | P0.10, P8.1 |
| kamal setup/deploy, SSL, db:prepare/seed | P8.2, P8.3 |
| 스모크·폴백 데모 검증 | P8.4 |

---

## 부록 B — RAILS_PLAN §17 검증 계획 ↔ Phase 게이트 매핑

| §17 검증 항목 | 검증 방법 | 커버 Phase 게이트 |
|------|------|------|
| 핵심 플로우 | Capybara: 작성→OCR/AI→승인→포인트·레벨 end-to-end | Phase 3 게이트, P8.4 |
| 실시간 | 교사·학생 2세션 Turbo Stream 반영 | P3.9, Phase 3 게이트 |
| 키 없는 폴백 | AI 규칙기반 무중단·사진OCR 비활성·키보드/원고지 정상 | P3.5, P3.6, Phase 3 게이트, P8.4 |
| 외부 연동 | Kakao/Naver·정보나루 실제 응답/graceful 폴백 | P5.1, P6.5 |
| 인가 경계 | Pundit 5역할 경계 위반 차단 | P2.8, Phase 6·7 게이트 |
| 배포 영속성 | 재배포 후 볼륨 데이터 유지·SSL·시드 | Phase 8 게이트 |
| 데이터 무결성 | 유효성·유니크(튜플 신원·학급 유일성) | Phase 1·2 게이트 |
| 대회 요건(연구06) | CSV 원자료(사전·사후 5축 비교) | P6.3 |

---

## 부록 C — 전역 위험 · 완화

| 위험 | 영향 | 완화 |
|------|------|------|
| **schools.js 원본 부재** | 6,331교 시드 불가 | P0.7에서 축소 시드/NEIS 재수집 결정, 프로덕션 시드는 후속 |
| **prototype/연구 문서 부재** | 프롬프트·상수 원문 없음 | P0.7에서 프롬프트(OCR/RUBRIC/VERIFY/QUIZGEN) 재작성 위치 확정, monsters.md는 존재하므로 Phase 4 무영향 |
| **API 키 미보유** | OCR/AI/도서/도서관 실호출 불가 | 폴백이 기본 동작(사진OCR만 비활성), 데모는 폴백 경로로 시연(§17) |
| **Ruby 4.0.5 vs 계획서 3.4** | gem 호환성 | 실제 4.0.5 기준 진행, Gemfile.lock으로 고정, CI에서 검증 |
| **SQLite 동시성** | 다중 쓰기 경합 | Solid Queue in-Puma·WAL 모드, 소규모 트래픽 전제(§14) |
| **몬스터 에셋 물량(72폼)** | 이미지 제작 부담 | Phase 1은 12라인(36폼)만 시드 후 확장(monsters.md §6.2) |
| **아동 사행성·대회 공정성** | 규정 위반 리스크 | 가챠·유료 부재(P4.5 DoD), AI 서버 경유 강제(§15) |

---

### 참고 문서
- 설계 확정: [`docs/RAILS_PLAN.md`](./RAILS_PLAN.md)
- 몬스터 도감 시드(72폼·YAML): [`docs/monsters.md`](./monsters.md)
- 프로토타입 분석: [`docs/11_프로젝트_분석_보고서.md`](./11_프로젝트_분석_보고서.md)
