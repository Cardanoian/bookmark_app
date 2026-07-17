# 「책갈피」 TODO

> 앞으로 해야 할 작업 정리. 최종 수정: 2026-07-17
> 참고 문서: [`docs/IMPLEMENTATION_PLAN.md`](docs/IMPLEMENTATION_PLAN.md) · [`docs/RAILS_PLAN.md`](docs/RAILS_PLAN.md) · [`docs/monsters.md`](docs/monsters.md) · [`docs/API_KEYS.md`](docs/API_KEYS.md) · [`DESIGN.md`](DESIGN.md) · [`DESIGN_CHANGE_PLAN.md`](DESIGN_CHANGE_PLAN.md)

## 현재 상태 (baseline)

- **앱 구현 Phase 0~8 완료.** 인증·역할, 독후감·AI 파이프라인, 게이미피케이션·몬스터 도감, 콘텐츠·커뮤니티, 역할별 도구(교사/사서/교육청/총괄), 배포 설정까지 구현됨.
- **테스트 497 runs / 0 failures**, rubocop 무경고, brakeman 0. (전체 점검 Phase 0~3 하드닝 + Gemini API 실동작화 + 몬스터 도감 전량 시드 반영)
- **외부 API 키 4종 주입 완료**(Gemini·네이버·정보나루) — 암호화 credentials. 도서검색은 네이버 단독.
- 아래는 **아직 남은 작업**이다.

## ⭐ 다음 추천 실행 순서

> 남은 작업을 **리스크·의존성·비용** 기준으로 정렬한 권장 순서(강제 아님, 오너 우선순위에 따라 재배열 가능). **각 항목의 상세 정의·기술 배경은 아래 카테고리 섹션에 있고, 여기서는 순서 근거만 적는다.**
>
> 최근 완료: 하드닝 Phase 0~3 5커밋 로컬 main 병합(미push) · 외부 API 3종 실호출 검증(Gemini 결함 2건 수정) · **몬스터 도감 24라인 72폼 전량 시드(dex_complete 보상 루프 닫힘, 2026-07-08)** · **OCR 실사진 라이브 검증(손글씨 2장 정확 인식, 2026-07-08)** → 이로써 4종 API 경로 전량 실검증 완료.

1. **🔴 배포 준비** *(→ 배포)* — 드로플릿·레지스트리 자격이 확보되면 착수하는 마일스톤.
2. **🔵 모니터링·에러 트래킹** *(→ 품질·운영)* — 아래 3.2 착수 판단의 관측 근거라 배포와 함께 세팅 권장.
3. **`git push origin main`** *(자격 확보 시 상시)* — 현재 로컬 main이 origin보다 앞서 있음(미push). 인증되면 원격 동기화.

---

## 남은 작업

### 🔴 배포 (프로덕션 올리기 전 필수)

- [ ] **실제 원격 배포** — `kamal setup` → `kamal deploy`. 현재는 로컬 부팅 검증까지만 완료(드로플릿·레지스트리 자격 부재로 미실행).
- [ ] **실 도메인 설정** — `config/deploy.yml`의 `proxy.host`가 플레이스홀더(`chaekgalpi.example.com`). 실 호스트로 교체 + DNS + SSL(kamal-proxy Let's Encrypt 자동).
- [ ] **메일러 호스트** — `config/environments/production.rb`의 `default_url_options` host가 `example.com`. 실 도메인으로 교체(비밀번호 재설정 등 메일 발송 시 SMTP 자격도).
- [ ] **프로덕션 시크릿 주입** — 서버에 `RAILS_MASTER_KEY`(= `config/master.key` 내용)만 주입하면 credentials 자동 복호화. 절차: [`docs/API_KEYS.md`](docs/API_KEYS.md) §3.2.
- [ ] **Active Storage 프로덕션 스토리지** — 현재 local disk 서비스. 서버 재생성 시 업로드(사진·낭독 녹음) 유실 방지를 위해 DigitalOcean Spaces(S3 호환) 등 영속 스토리지 검토.
- [ ] **SQLite 데이터 영속성** — `storage/production*.sqlite3` 4개 DB(primary/cache/queue/cable)의 kamal 볼륨 마운트·백업 전략 확인.
- [ ] **잡 워커** — 현재 `SOLID_QUEUE_IN_PUMA: true`(Puma 내 실행)로 단일 서버엔 충분. 트래픽 증가 시 전용 job 서버 분리(`deploy.yml`의 `servers.job`).

### 🟡 콘텐츠·데이터 완성

> **엔지니어링 완료(2026-07-13)** — 학교 전량 적재 파이프라인·다밴드 도서 카탈로그·6,300교 다운스트림 스케일 수정을 구현했다. 남은 것은 **실데이터 확보**뿐이며, 데이터가 없어도 축소 시드/no-op 로 앱은 정상 동작한다.

- [ ] **학교 전량 시드 — 실데이터 적재 대기** — 파이프라인 구현 완료(`schools:fetch`→`db/seeds/schools.csv`→`schools:seed_full`(`upsert_all`), `Schools::GuParser`·`Schools::NeisFetcher`, `address` 컬럼, dev/test 축소 17교·prod no-op 가드). 다운스트림 스케일도 반영(가입/로그인 하이브리드 피커[시도→시군구+이름검색]·스코프 학급 엔드포인트·전국 랭킹 Top100+본인학교 행). **남은 일: NEIS OpenAPI authKey 발급(무료) → `bin/rails schools:fetch` → CSV 커밋 → prod 에서 `schools:seed_full` 1회.**
- [ ] **도서 카탈로그 확장 — 목록 추가 확장 여지** — 34권 단일밴드 → **97권 3밴드(초등 1~2/3~4/5~6) 큐레이션**으로 확장(`Book::GRADE_BANDS` 표준화, `books:seed` 재작성) + 메타 자동보강 `books:enrich`(네이버, `Books::CatalogEnricher`) 추가. **남은 일: 학교도서관저널 전체 목록으로 큐레이션 배열 추가 확장(선택), 네이버 키로 `books:enrich` 실행해 표지/ISBN 채우기.**

### 🔵 품질·테스트·운영

- [ ] **브라우저/시스템 테스트** — 현재 headless Chrome 부재로 model/request/integration/policy 테스트만. Stimulus·Turbo 상호작용 E2E 커버리지 추가 검토.
- [ ] **접근성(UDL)** — STT/TTS·원고지·낭독 녹음 등 실기기 검증.
- [ ] **성능** — 대시보드·랭킹·도감의 N+1 쿼리 점검, 인덱스 확인. (전체 점검 Phase 3에서 3.1 랭킹 그룹 SQL·3.3 카운터캐시·3.4 대시보드 집계+페이지네이션·3.5 인덱스 반영 완료.)
- [ ] **(성능·의도적 보류) 3.2 게임화 재계산 백그라운드 이관** — `award_points → refresh_badges!/check_evolution!/ReadingStats` 재계산을 웹 요청 스레드에서 백그라운드 잡으로 이관.
  - **지금 보류하는 이유:** ① 2.2 메모이제이션으로 요청당 쿼리는 이미 감소, ② Architect 분석상 백그라운드 이관은 웹 응답 **지연**만 완화하고 단일 SQLite **쓰기 경합**은 완화 못 함(잡도 동일 primary writer), ③ 비동기화 시 뱃지·레벨업·진화·랭킹이 **즉각 반영되지 않아**(eventual consistency) 미성년자 게임화의 즉각 피드백 UX가 저하됨.
  - **착수 트리거(이 중 하나라도 관측되면):** 프로덕션 실부하에서 SQLite `database is locked`(쓰기 타임아웃) 발생 / 퀴즈 완료·교사 점수부여 응답이 체감상 지연 / 동시 쓰기 병목이 모니터링에 잡힐 때.
  - **착수 시 필수:** 게임화 즉각성 통합 테스트를 `perform_enqueued_jobs` 로 재작성, 뱃지·진화의 "한 박자 늦은" 표시를 UX(로딩/폴링/Turbo Stream)로 보완.
- [ ] **모니터링·에러 트래킹** — 프로덕션 로깅/에러 리포팅 도구 도입 검토. 위 3.2 항목의 **착수 트리거(SQLite `database is locked`·응답 지연·쓰기 병목)를 실측으로 포착**하는 관측 인프라 역할을 겸한다.

### 🎮 게임 운영 후속 (초기값·정책 구현 완료 · 운영 튜닝 가이드)

> 재롤·워밍 상한과 무게이트 롤아웃을 **초기값·정책으로 확정해 구현**했다. 앞으로는 아래 「운영 튜닝 가이드」대로 **실사용을 보며 값만 조정**하면 된다.

#### ✅ 구현 완료
- [x] **재롤·워밍 rate limit/예산 초기값 확정** — `REGENERATE_PER_USER` 10회/시간(유지)·`WARMING_PER_USER` 20회/시간(유지)·`WARMING_DAILY_BUDGET` **500→5000회/일**(상향).
- [x] **무게이트 롤아웃 — 전체 학급 파일럿 + 신고 자동숨김 2건 + 교사 알림 구현** —
  - **파일럿 범위 = 전체 학급**: `on_demand_games=true`(seeds 기본)라 모든 학급이 파일럿(교사팀이 학생 계정으로 베타테스트). 사고 학급은 스코프 플래그(`on_demand_games:classroom:<id>=false`)로 개별 격리.
  - **신고 자동 숨김 = 서로 다른 2명**: `quiz_reports`(1인 1신고 unique)·`quizzes.reports_count`(counter_cache) + `ContentProvider.record_report!`. `REPORT_HIDE_THRESHOLD=2` 도달 시 자동 숨김+재생성. 게임 뷰 🚩신고 버튼(system 판만)·`Games::ContentReportsController`.
  - **교사 알림 = 대시보드 사후 검토**: 신고 접수 시 신고자 학급 담임의 교사 대시보드 "🚩 신고된 게임 콘텐츠" 섹션에 노출. 테스트 5건.

#### 📘 운영 튜닝 가이드 (서비스 굴리며 이렇게 조정한다)

> 아래 값들은 **실사용 데이터가 쌓이면 조정**하는 것들이다. "언제·왜 올리고 내리는지"와 "어느 파일을 고치는지"를 적어 둔다. 관측(모니터링) 도입 전에는 초기값 그대로 두고, 도입 후 실측 분포로 재산정한다.

**① 재롤·워밍 상한** (`app/services/rate_limiter.rb`, `app/services/games/content_provider.rb`)

- **`WARMING_DAILY_BUDGET`(현재 5000회/일)** — 하루에 서비스 **전체**가 AI(Gemini)로 게임 문제를 미리 만드는 최대 횟수. AI 호출은 **돈·할당량**이 든다.
  - *올려야 할 때*: 로그/모니터링에 예산 초과로 워밍이 자주 스킵돼 학생이 **AI 문제 대신 오프라인(간이) 문제를 많이 보게** 될 때.
  - *내려야 할 때*: Gemini **비용·할당량**이 부담될 때.
  - *감 잡는 법*: 대략 "하루에 새로 등장하는 (책 × 학년군 × 콘텐츠축) 조합 수". 파일럿 인원이 늘수록 커진다. 5000은 소~중규모 파일럿 여유값이며, 전교·다교로 확대되면 실측 후 키운다.
- **`WARMING_PER_USER`(현재 20회/시간)** — 한 학생 때문에 시간당 유발되는 워밍 상한. 한 명이 여러 책을 빠르게 넘겨도 예산을 독식하지 못하게 한다.
  - *올림*: 열심히 하는 학생이 새 책 워밍이 자주 막힐 때. *내림*: 특정 학생이 워밍을 과하게 유발할 때.
- **`REGENERATE_PER_USER`(현재 10회/시간)** — "🎲 다시 뽑기" 시간당 상한. 누를 때마다 새 문제 세트가 **DB에 쌓여** 저장공간을 먹으므로 상한을 둔다.
  - *올림*: 학생이 정당하게 다시 뽑기를 자주 원하는데 막힐 때. *내림*: DB/스토리지 증식이 부담될 때.
- **무엇을 보고 정하나**: 모니터링 도입 후 ① 워밍 스킵률(예산/rate 초과 로그) ② Gemini 호출량·비용 ③ 재롤 빈도 ④ AI vs 오프라인 노출 비율.

**② 무게이트 롤아웃 조정** (`app/services/games/content_provider.rb`, 관리자 `admin/settings`)

- **신고 자동 숨김 임계 `REPORT_HIDE_THRESHOLD`(현재 2)** — 서로 다른 몇 명이 신고하면 콘텐츠를 자동으로 숨길지.
  - *올림(3+)*: 장난·오신고가 많아 **정상 콘텐츠가 억울하게 자주 숨겨질** 때.
  - *내림(1)*: 부적절 콘텐츠가 **한 명만 신고해도 즉시** 내려가야 하는 리스크 민감 시기.
  - 파일럿 신고 데이터의 **오신고 비율**을 보고 정한다.
- **파일럿 범위(피처플래그 `on_demand_games`, `admin/settings`)** — 사고 난 학급만 끄기 = `on_demand_games:classroom:<id>=false`, 전체 즉시 중단(하드 kill) = `on_demand_games=false`. 파일럿이 안정되면 그대로 두고 **문제 학급만 스코프로 격리**한다.
- **교사 알림 확장(후속 여지)** — 현재는 대시보드에서 교사가 확인하는 방식(pull). 신고가 많아지면 **미확인 배지·상단 알림·이메일**로 능동 알림(push)을 얹을 수 있다(별도 후속).
- **볼 지표**: 콘텐츠당·학급당 신고율, 오신고 비율, 자동 숨김 후 재신고율.

#### 🔧 후속 여지 (nice-to-have · 급하지 않음)

> 아키텍트 검증(APPROVE)에서 나온 비차단 개선점. **둘 다 하위 계층이 이미 방어**해 지금 고치지 않아도 무해하며, 필요/여유 시 다듬는다.

- [ ] **동시 신고 이중 재생성 정리** — 서로 다른 두 학생이 거의 동시에(밀리초 내) 같은 콘텐츠를 신고하면 `record_report!` 의 `!quiz.reported?` 판정이 reload 이전 stale 값을 읽는 창 때문에 `report!` 가 두 번 호출돼 재생성 잡이 2건 적재될 수 있다. **무해한 이유**: `report!` 의 숨김은 멱등(`reported: true` 재대입), 두 재생성 잡은 `GenerateGameContentJob#claim_warming` 의 `(book, band, axis, version)` 부분 유니크 인덱스에서 1건으로 수렴(나머지는 RecordNotUnique→no-op). SQLite 단일 writer라 실익도 작다. *다듬으려면*: `content_provider.rb` 의 판정을 트랜잭션 내 조건부 업데이트(예: `Quiz.where(id:, reported: false).update_all(reported: true)` 영향 행수로 승자 결정) 또는 `with_lock` 로 좁혀 잉여 잡 적재를 원천 제거.
- [ ] **학급 없는 학생(orphan) 신고 가시성** — 학급/학년 미상 학생의 신고는 **자동 숨김(임계 2)은 정상 작동**하지만, 어느 담임의 `@students`(학급 소속)에도 안 들어가 **어떤 교사 대시보드에도 표시되지 않는다**. *다듬으려면*: orphan 신고를 총괄(superadmin) 모더레이션 화면 등에서 확인할 경로를 추가(안전장치 자체는 이미 작동하므로 관측 보강용).

### 🎨 디자인 개편 후속 (1차 묶음 완료 · 이월 작업)

> **1차 묶음 완료(2026-07-17)** — `DESIGN_CHANGE_PLAN.md` 기반으로 **디자인 시스템 기반 + 대표 화면**을 개편했다(작업 트리, 미커밋). 구현: Tailwind v4 `@theme` 토큰(`DESIGN.md` 색·폰트·라운드 1:1 매핑, 기본 팔레트 유지로 기존 뷰 무회귀) · Pretendard 자체호스팅(`app/assets/fonts`, CSP `font_src :self`) · 공통 컴포넌트(`.btn*`/`.card*`/`.form-*`/`.badge*`/`.page-shell*`/`.state-banner*`/`.progress-bar`) · 유동 레이아웃(`application`·`admin` 오프캔버스 사이드바) · 학생 대시보드·로그인/가입 4화면·독후감 index/show/new/edit + partial. **Turbo Stream·Stimulus·Pundit 계약 전량 보존**, `bin/rails test` 746 runs 0 failures, architect APPROVED, deslop 완료. 아래는 이월 작업이다.

#### 🧹 비차단 정리 (지금 정리 대상 · 방금 만든 디자인 시스템 마무리 · 범위 좁고 저위험)

> 계약 변경 없이 신규 토큰·컴포넌트로 통일하는 작은 후속. 한 번의 정리 패스 + `bin/rails test` 회귀로 충분.

- [ ] **D4 · 배지 팔레트 이관** — `app/helpers/reports_helper.rb`의 `ai_status_badge`/`level_badge`가 아직 옛 팔레트(하드코딩 색) → 신규 `.badge-*`(`.badge-neutral/-yellow/-success/-info`) 토큰으로 이관.
- [ ] **OCR 상태색 통일** — `app/views/ocr/create.turbo_stream.erb`의 `#ocr_status`가 옛 `text-sky-700` → 디자인 토큰 색(예: `text-brand-blue`)으로 통일. (`id=ocr_status` 계약 유지)
- [ ] **D3 · 로그인/가입 폼 폭 정합** — `sessions/{new,student_new,staff_new}.html.erb`·`registrations/new.html.erb`가 `max-w-md/max-w-lg`로 남음 → `.page-shell-form`(또는 카드 자체 max-width)과의 정합 여부 판단 후 통일.
- [ ] **D5 · 마감 디테일** — `.btn-icon` 40px 터치타깃 확인 · `shared/_student_nav`의 hover 처리 · 각 화면 `<h1>` 이모지에 `aria-hidden="true"` 일괄 적용.

#### 📦 Phase 4~8 화면군 확장 (화면군 단위 별도 묶음 · 공통 컴포넌트 그대로 확장)

> 각 Phase가 독립된 큰 작업이므로 **한 화면군씩** 스코프를 잡아 진행(한꺼번에 몰면 검증이 흐려짐). 학생 사용 빈도 순으로 Phase 4가 자연스러운 다음 순서.

- [ ] **Phase 4 · 게이미피케이션** *(권장 다음 순서)* — 게임 허브·독서게임 5종 플레이 화면·몬스터 도감/진화 로드맵·상점·미션·랭킹(Top100).
- [ ] **Phase 5 · 커뮤니티** — 게시판(`topics`/`board_posts`/`forum_posts`)·좋아요·응원 UI.
- [ ] **Phase 6 · 역할별 심화 화면** — 교사(검토·통계·학급관리)·사서(도서관)·교무관리자 대시보드/도구.
- [ ] **Phase 7 · 관리자 콘솔 CRUD** — `/admin` 콘솔 전체 CRUD 화면(오프캔버스 사이드바 위 컨텐츠 영역).
- [ ] **Phase 8 · 부가 표면** — 인쇄용 뷰·메일러 템플릿·PWA·잔여 Turbo/뷰 정리.

---

## 완료·결정 이력

### 🟢 기능 마무리 — 게시판 글 좋아요(2026-07-13 완료)

> `forum_post`에 모델 메서드만 있고 라우트·UI가 없던 좋아요를 cheer(응원)·quiz_report(신고) 패턴 재사용으로 완결했다.

- `ForumPostLike`(`(forum_post, user)` 유일성=1인 1좋아요) + `forum_posts.likes_count` counter_cache.
- 라우트(`resources :forum_posts, only: []` 하위 단수 `resource :like`)·`ForumPostLikesController`(`create`/`destroy`, RecordNotUnique 무해 처리, destroy no-op 시 `skip_authorization`) + Turbo Stream 버튼 갱신.
- `ForumPostLikePolicy` — 생성은 `TopicPolicy#show?` 위임(토픽 열람 가능 경계 안 사용자만), 취소는 본인 좋아요만.
- 뷰: `forum_post_likes/update.turbo_stream.erb` + `topics/_like_button` partial(토글 버튼+카운트), `topics/_forum_post`가 정적 카운트 대신 이를 렌더.
- 모델·통합 테스트 추가.

### 🎮 온디맨드 게임 AI 출제 (완료 · **독서게임 5종**)

> **R1(코어 온디맨드) + 게임 5종 축소 완료** — 브랜치 `feat/game-ai-ondemand-r2`(커밋 `2195bf0`, r1 `46c3c88` 위), RuboCop·Brakeman 클린(**main 병합 완료** · 자격 확보 시 push). 교육 다양성 우선으로 독서게임을 **5종(quiz·classic·vocab·whoami + book)** 으로 확정. 상세 변경 이력은 git 로그 참조.

#### ✅ 완료 — 독서게임 5종 온디맨드

- **5종**: `quiz`(독해·mcq)·`classic`(고전·mcq)·`vocab`(어휘·matching)·`whoami`(추론·hint_reveal) + **`book`(책 소개 대결, 소셜·신규 실구현)**.
- **학생 온디맨드 AI 출제**(교사 검수 게이트 없이 즉석 플레이) + 무키/실패 시 `book.summary` 파생 결정적 오프라인으로 **무중단 폴백**(하드코딩 오답 제거).
- 콘텐츠축 3축(mcq/matching/hint_reveal) 캐시(비용 봉인·N1)·워밍 잡·`QuizModerator`(구조검증+금칙어)·**스코프형 kill switch/피처플래그**(무게이트 유지, 학급/학교 사고 격리)·부분 유니크 dedup(정수 술어)·`RateLimiter`.
- 채점기 4종(mcq_single·mcq_multi·matching·hint_reveal)·**origin 분기 멱등 델타**(재롤·표면전환 파밍 0)·**hint_reveal 서버권위**(위조·attempt_id 생략 이중 차단)·**플레이/제출 band·학급 클램프**(온디맨드 + 선존 크로스-학급 퀴즈 id 플레이 구멍 봉인).
- **book**: `board_post`/`cheer` 패턴 재사용 — `book_intros`/`book_intro_votes`(**소개당 1인 1표** unique·counter_cache) + `BookIntro`/`BookIntroVote` + `BookIntroPolicy`(경계=학급, 크로스-학급·자기 소개 투표 차단) + `Games::BookController`(play/create/vote/unvote) + play 뷰(정적 작성 가이드) + 통합 테스트. **텍스트만·Gemini/Quiz 미생성(assert)**.
- 앱 전반 하드닝(로그인 fail2ban·FK on_delete·페이지네이션·전교 집계 SQL화·admin 포인트 award 체인·미테스트 모델 백필). 마트료시카 CLAUDE.md 동기화 + README·TODO. **전체 그린**(RuboCop·Brakeman 클린).

#### 🟡 후속 정밀화 — 하드닝 4건 완료 · 결정 2건 확정 · 프로덕션 보류 2건 (브랜치 `refine/followup-hardening`)

> 검증에서 이관된 비차단 LOW 항목 정리. **코드로 답이 분명한 4건(2·3·4·5)은 구현·테스트**, **정책/데이터 결정 2건(1·6)은 결론 확정**, **실운영 데이터·오너 정책이 필요한 2건(7·8)은 트리거와 함께 보류**한다. 전체 그린(RuboCop·Brakeman 클린).

##### ✅ 구현 완료 (하드닝)

- [x] **학급 없는 학생 band 처리(Phase 3 리뷰 LOW)** — `ReadingDomain.game_band_for` 신설: 학년 미상(nil/0)을 기본 최고 밴드(g56)가 아니라 **최저 밴드(g12)** 로 고정한다(눈높이 안 맞는 콘텐츠 노출·"미상=최고밴드 통과" 느슨함 제거). `ContentProvider`(resolve/regenerate)와 `QuizPolicy#within_band?`가 같은 함수를 써 **생성 밴드=인가 밴드**로 일치(무대기 플레이 보존, 403 없음). 첨삭·다학년 대시보드의 `band_for`(g56 폴백)는 불변. 테스트 3건.
- [x] **whoami play 미확정 attempt 재사용(Phase 3 리뷰 LOW)** — `whoami#play`가 같은 퀴즈의 **미확정(played_at nil)** 선생성 attempt 를 재사용한다. 매 진입 0점 빈 attempt 누적을 없애고, 힌트 공개 후 재진입으로 **힌트 카운터 0 새 판**을 얻는 페널티 우회(H2)도 닫는다(확정 attempt 는 재사용 안 함 → 새 판 정상 시작). 테스트 2건.
- [x] **로그인 XFF/trusted_proxies 명시(Phase 6 리뷰 LOW)** — `production.rb`에 `config.action_dispatch.trusted_proxies`를 kamal/도커 사설 대역+루프백으로 **명시**(암묵 기본값 의존 제거, 감사가능). 근거: kamal-proxy 가 실 소켓 IP를 XFF 에 덧붙이고 `ip_spoofing_check`(기본 on)라 공인 클라이언트의 위조 XFF 로 `remote_ip` 조작 불가 + 계정축 스로틀은 IP 위조 무관. **배포 시 도커 브리지 실 CIDR 로 좁힐 것**.
- [x] **admin 포인트 음수/초과 target 정확 피드백(Phase 6 리뷰 LOW)** — 목표값을 **0 이상 정수만** 허용(음수·소수·문자는 저장 없이 정확히 거부), `spend_points!` 실패(잔액 초과) 시 거짓 "수정했어요" 대신 정직히 안내. edit 뷰에 `min:0`. 테스트 3건.

##### 🔵 결정 확정 (코드 변경 불요)

- [x] **표면 포인트 결합 정책 → 유지(결합)** — "콘텐츠축당 1회 보상"을 **유지**한다. 근거: ① 표면별 독립 보상은 같은 mcq 를 quiz·classic 로 두 번 푸는 파밍 유인, ② mcq 표면이 5종 축소로 quiz·classic 둘뿐이라 결합 체감이 이미 완화, ③ 뒤집으려면 `quiz_attempts.surface` 저장+델타키 확장 등 스키마 변경이 필요해 편익 대비 비용 큼. **비포인트 다양성 유인(뱃지·코스메틱)은 별도 기능**으로 후속(정밀화 범위 밖).
- [x] **오프라인 matching/hint 품질 하한 → 이미 구조적 보장** — `QuizDraftService#offline_matching`은 줄거리에서 뜻을 추측하지 않고 **보장된 정답 쌍만**(책 메타+band별 일반 독서 용어)으로 항상 정확히 5쌍을 채우고, `offline_hint_reveal`은 **항상 참인 힌트**(맥락→글자수→첫 글자)로 3타깃을 만든다. 요약 빈약·무키에서도 오답/거짓 힌트가 생기지 않는 하한이 이미 코드로 보장됨(품질 < AI 는 정직화). 추가 코드 불요.

### 🟡 콘텐츠·데이터 완성

- [x] ~~**몬스터 도감 절반 남음**~~ — 완료(2026-07-08). `db/seeds/monsters.yml` 24라인에 `phase` 명시(1·2 각 12라인) + `MonsterSeeder.seed_all!`(rake `monsters:seed`)로 **72폼 전량 시드**. `dex_complete`(분모 24) 이제 도달 가능 → 완성 보상 루프 닫힘. 테스트 3건 추가(전량 시드 무결성·phase2 조건·24라인 dex_complete).
- [x] ~~**몬스터 이미지 에셋**~~ — 완료(2026-07-12). 애니메이션 WebP 72종을 `app/assets/images/monsters/<image_key>.webp`에 설치하고 도감·상세·대표 몬스터·진화 로드맵에 연결. `monsters:install_assets`로 재설치 가능하며 누락 에셋은 이모지로 폴백.

### 🔵 외부 API 실연동 검증 (2026-07-07 실호출 완료)

> 세 API 모두 **실제로 호출해 응답 필드 매핑을 검증**했다. 검증 중 Gemini 경로에서 치명 결함 2건을 발견·수정(아래). 실패 시 폴백(로컬 캐시·규칙기반·CSV)은 여전히 무중단 동작.

- [x] **Gemini 실응답 검증** — 5축 첨삭/퀴즈/진위 응답 JSON 구조가 `Ai::*` 파싱과 일치 확인(rubric 5축 content·emotion·life·structure·spelling, questions[prompt/choices/answer_index], suspicion/reasons). **검증 중 결함 2건 수정:**
  - 🐞 **systemInstruction 형식 오류** — `GeminiClient` 가 `systemInstruction` 을 문자열로 보내 **모든** system_instruction 사용 호출(첨삭·퀴즈·진위·OCR)이 HTTP 400 → 조용히 폴백. 즉 AI 기능 전부가 규칙기반/오프라인으로만 동작 중이었음. `{ parts: [{ text: }] }` Content 구조체로 감싸 수정.
  - 🐞 **타임아웃 과소(8s)** — 5축 첨삭 실측 지연 ~16s 인데 per-attempt 8s 라 위 수정 후에도 첨삭은 매 시도 타임아웃 → 폴백. 30s 로 상향(첨삭·OCR 은 백그라운드 잡, 동기 경로는 8s 미만이라 무영향).
  - [x] **OCR(사진→텍스트) 실이미지 검증 완료(2026-07-08)** — 실제 손글씨 독후감 사진 2장(피그말리온·강아지똥, 원고지)을 `Ai::OcrService` 프로덕션 경로로 라이브 호출(gemini-2.5-flash Vision). **인식 정확도 우수**(피그말리온 434자/7.5s, 강아지똥 650자/9.3s — 오탈자 거의 없음). `response["text"]` 매핑·Base64 `inlineData` 인코딩·JSON 파싱 정상 확인. **부수 성과:** 강아지똥이 9.3s라 과거 8s 타임아웃이면 실패 → 30s 상향 수정(Gemini 하드닝)의 필요성이 실측으로 재확인됨.
- [x] **네이버 도서검색 실응답 검증** — HTTP 200, `items[]` 의 title/author/publisher/image/isbn/description 6개 필드 전부 존재·매핑 일치. isbn13 단일값 정상. `app/services/books/search_service.rb`.
- [x] **정보나루 실응답 검증** — 과거 확정 기간(예: 2025-06) HTTP 200, `response.docs[].doc` 의 bookname/isbn13/loan_count 매핑 일치(loan_count 는 문자열→`.to_i`). **주의:** 직전 달 데이터가 아직 미집계면 8s 타임아웃 → CSV 폴백(정상 열화). `app/services/library/data4library_service.rb`.
