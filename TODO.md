# 「책갈피」 TODO

> 앞으로 해야 할 작업 정리. 최종 수정: 2026-07-23
> 참고 문서: [`docs/monsters.md`](docs/monsters.md) · [`docs/API_KEYS.md`](docs/API_KEYS.md) · [`DESIGN.md`](DESIGN.md)

## 현재 상태 (baseline)

- **앱 구현 Phase 0~8 완료.** 인증·역할, 독후감·AI 파이프라인, 게이미피케이션·몬스터 도감, 콘텐츠·커뮤니티, 역할별 도구(교사/사서/교육청/총괄), 배포 설정까지 구현됨.
- **테스트 497 runs / 0 failures**, rubocop 무경고, brakeman 0. (전체 점검 Phase 0~3 하드닝 + Claude API 실동작화 + 몬스터 도감 전량 시드 반영)
- **외부 API 키 4종 주입 완료**(Claude·네이버·정보나루) — 암호화 credentials. 도서검색은 네이버 단독.
- 아래는 **아직 남은 작업**이다.

## ⭐ 다음 추천 실행 순서

> 남은 작업을 **리스크·의존성·비용** 기준으로 정렬한 권장 순서(강제 아님, 오너 우선순위에 따라 재배열 가능). **각 항목의 상세 정의·기술 배경은 아래 카테고리 섹션에 있고, 여기서는 순서 근거만 적는다.**
>
> 최근 완료: 하드닝 Phase 0~3 5커밋 로컬 main 병합(미push) · 외부 API 3종 실호출 검증(Claude 결함 2건 수정) · **몬스터 도감 24라인 72폼 전량 시드(dex_complete 보상 루프 닫힘, 2026-07-08)** · **OCR 실사진 라이브 검증(손글씨 2장 정확 인식, 2026-07-08)** → 이로써 4종 API 경로 전량 실검증 완료. · **디자인 개편(2026-07-17) 완료** → 남은 것은 실기기 다중 뷰포트 시각 QA(아래 🔵 「브라우저/시스템 테스트」와 동일 범위)뿐.

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

> **학교 전량 데이터 완료(2026-07-18)** — NEIS 국내 17개 시도교육청 초등학교 6,333교 스냅샷을 확보했고, 안전한 갱신·비활성화 파이프라인과 전국 규모 피커를 적용했다.

- [x] **학교 전량 시드** ✅ **완료(2026-07-18)** — NEIS `schoolInfo` 전 페이지를 전체 건수 기준으로 수집하고 국내 17개 교육청·코드 보유 초등학교 **6,333교**를 `db/seeds/schools.csv`에 저장. 17개 교육청/최소 건수/필수값/코드 중복 검증, 재시도, 원자적 CSV 교체, 배치 upsert, 누락 NEIS 학교 비활성화(`active`), 수동 학교 보존(`data_source`), 개교예정 무코드·재외교육청 제외를 구현했다. `db:seed`는 CSV가 있으면 전량 적재하고 파일이 없는 체크아웃만 축소 17교로 폴백한다.
- [ ] **도서 카탈로그 확장 — 목록 추가 확장 여지** — 34권 단일밴드 → **97권 3밴드(초등 1~2/3~4/5~6) 큐레이션**으로 확장(`Book::GRADE_BANDS` 표준화, `books:seed` 재작성) + 메타 자동보강 `books:enrich`(네이버, `Books::CatalogEnricher`) 추가. **남은 일: 학교도서관저널 전체 목록으로 큐레이션 배열 추가 확장(선택), 네이버 키로 `books:enrich` 실행해 표지/ISBN 채우기.**

### 🔵 품질·테스트·운영

- [ ] **브라우저/시스템 테스트** — 현재 headless Chrome 부재로 model/request/integration/policy 테스트만. Stimulus·Turbo 상호작용 E2E 커버리지 추가 검토. (디자인 개편 후 남은 실기기 다중 뷰포트 시각 QA도 이 범위.)
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

- **`WARMING_DAILY_BUDGET`(현재 5000회/일)** — 하루에 서비스 **전체**가 AI(Claude)로 게임 문제를 미리 만드는 최대 횟수. AI 호출은 **돈·할당량**이 든다.
  - *올려야 할 때*: 로그/모니터링에 예산 초과로 워밍이 자주 스킵돼 학생이 **AI 문제 대신 오프라인(간이) 문제를 많이 보게** 될 때.
  - *내려야 할 때*: Claude **비용·할당량**이 부담될 때.
  - *감 잡는 법*: 대략 "하루에 새로 등장하는 (책 × 학년군 × 콘텐츠축) 조합 수". 파일럿 인원이 늘수록 커진다. 5000은 소~중규모 파일럿 여유값이며, 전교·다교로 확대되면 실측 후 키운다.
- **`WARMING_PER_USER`(현재 20회/시간)** — 한 학생 때문에 시간당 유발되는 워밍 상한. 한 명이 여러 책을 빠르게 넘겨도 예산을 독식하지 못하게 한다.
  - *올림*: 열심히 하는 학생이 새 책 워밍이 자주 막힐 때. *내림*: 특정 학생이 워밍을 과하게 유발할 때.
- **`REGENERATE_PER_USER`(현재 10회/시간)** — "🎲 다시 뽑기" 시간당 상한. 누를 때마다 새 문제 세트가 **DB에 쌓여** 저장공간을 먹으므로 상한을 둔다.
  - *올림*: 학생이 정당하게 다시 뽑기를 자주 원하는데 막힐 때. *내림*: DB/스토리지 증식이 부담될 때.
- **무엇을 보고 정하나**: 모니터링 도입 후 ① 워밍 스킵률(예산/rate 초과 로그) ② Claude 호출량·비용 ③ 재롤 빈도 ④ AI vs 오프라인 노출 비율.

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

### 🎨 디자인 개편 (완료)

- [x] **디자인 시스템 기반 + 전 화면 개편 완료(2026-07-17)** — Tailwind v4 `@theme` 토큰(`DESIGN.md` 색·폰트·라운드 매핑)·Pretendard 자체호스팅·공통 컴포넌트(`.btn*`/`.card*`/`.form-*`/`.badge*`/`.page-shell*` 등)로 로그인/가입·학생 대시보드·독후감·게이미피케이션(도감·진화·상점·미션·랭킹)·커뮤니티(게시판·토론방)·역할별 콘솔(교사·사서·교무)·관리자 CRUD·부가 표면(인쇄물·메일러·PWA)까지 전 화면을 개편. Turbo Stream·Stimulus·Pundit 계약 전량 byte-보존, 매 단계 architect·code-reviewer 승인, 최종 760 테스트 그린, raw 팔레트 잔존 0.
- 남은 일: 실기기 다중 뷰포트 시각 QA(위 🔵 「브라우저/시스템 테스트」 항목과 동일 범위).

---

## 완료·결정 이력

- [x] **게시판 글 좋아요 기능 완결(2026-07-13)** — `forum_post`에 모델 메서드만 있고 라우트·UI가 없던 좋아요를 cheer(응원)·quiz_report(신고) 패턴 재사용으로 완결. `ForumPostLike`(1인 1좋아요 unique) + counter_cache, 라우트·컨트롤러·정책·Turbo Stream 버튼, 모델·통합 테스트.
- [x] **온디맨드 게임 AI 출제 — 독서게임 5종(완료)** — quiz(독해)·classic(고전)·vocab(어휘)·whoami(추론)·book(책 소개 대결) 5종을 학생 온디맨드 AI 출제(교사 검수 게이트 없음)로 구현, 무키/실패 시 결정적 오프라인 폴백으로 무중단 동작. 콘텐츠축 캐시·워밍 잡·`QuizModerator`·스코프형 kill switch/피처플래그·부분 유니크 dedup·`RateLimiter`·채점기 4종·서버권위 힌트공개·band/학급 클램프 포함. 브랜치 `feat/game-ai-ondemand-r2`(커밋 `2195bf0`) main 병합 완료, RuboCop·Brakeman 클린.
- [x] **후속 정밀화 하드닝(완료, 브랜치 `refine/followup-hardening`)** — 코드 구현 4건(학급 없는 학생 band를 최저밴드로 고정, whoami 미확정 attempt 재사용, 로그인 XFF/trusted_proxies 명시, admin 포인트 입력 검증) + 정책 결정 확정 2건(표면 포인트 결합 유지, 오프라인 matching/hint 품질 하한은 이미 구조적 보장). 전체 그린(RuboCop·Brakeman 클린).
- [x] **몬스터 도감 72폼 전량 시드(2026-07-08)** — `db/seeds/monsters.yml` 24라인에 `phase` 명시 + `MonsterSeeder.seed_all!`(rake `monsters:seed`)로 72폼 전량 시드. `dex_complete`(분모 24) 도달 가능해져 완성 보상 루프가 닫힘. 테스트 3건 추가.
- [x] **몬스터 이미지 에셋(2026-07-12)** — 애니메이션 WebP 72종을 `app/assets/images/monsters/`에 설치하고 도감·상세·대표 몬스터·진화 로드맵에 연결. `monsters:install_assets`로 재설치 가능, 누락 에셋은 이모지로 폴백.
- [x] **외부 API 실연동 검증 완료(2026-07-07~08)** — Claude·네이버 도서검색·정보나루 3종 모두 실제로 호출해 응답 필드 매핑을 검증. Claude 경로에서 치명 결함 2건(systemInstruction을 문자열로 보내 전 AI 기능이 조용히 폴백하던 형식 오류, 5축 첨삭 실측 지연 대비 과소했던 8s 타임아웃)을 발견·수정(30s로 상향). OCR(사진→텍스트)은 실제 손글씨 독후감 사진 2장으로 라이브 검증 완료(2026-07-08, 정확도 우수, 강아지똥 9.3s 처리로 타임아웃 상향의 필요성 재확인). **당시 검증은 claude-haiku-4-5 Vision 기준이며, 현재 앱 모델은 `claude-haiku-4-5`(`app/services/ai/claude_client.rb`)로 교체되어 있다.** 실패 시 폴백(로컬 캐시·규칙기반·CSV)은 여전히 무중단 동작.
