# 「책갈피」 TODO

> 앞으로 해야 할 작업 정리. 최종 수정: 2026-09-04
> 참고 문서: [`docs/monsters.md`](docs/monsters.md) · [`docs/API_KEYS.md`](docs/API_KEYS.md) · [`DESIGN.md`](DESIGN.md) · [`android/README.md`](android/README.md) · [`android/DEVICE_VERIFICATION.md`](android/DEVICE_VERIFICATION.md)
>
> ⚠️ 아래 「현재 상태(baseline)」와 🟡·🔵 절의 일부 수치는 **2026-07 기준으로 낡았다**(테스트는 497 → **1785+**). 📱 Android 절과 🔴 배포 절만 2026-09-04 기준으로 갱신돼 있다.

## 현재 상태 (baseline)

- **앱 구현 Phase 0~8 완료.** 인증·역할, 독후감·AI 파이프라인, 게이미피케이션·몬스터 도감, 콘텐츠·커뮤니티, 역할별 도구(교사/사서/교육청/총괄), 배포 설정까지 구현됨.
- **테스트 497 runs / 0 failures**, rubocop 무경고, brakeman 0. (전체 점검 Phase 0~3 하드닝 + Claude API 실동작화 + 몬스터 도감 전량 시드 반영)
- **외부 API 키 4종 주입 완료**(Claude·네이버·정보나루) — 암호화 credentials. 도서검색은 네이버 단독.
- 아래는 **아직 남은 작업**이다.

## ⭐ 다음 추천 실행 순서

> 남은 작업을 **리스크·의존성·비용** 기준으로 정렬한 권장 순서(강제 아님, 오너 우선순위에 따라 재배열 가능). **각 항목의 상세 정의·기술 배경은 아래 카테고리 섹션에 있고, 여기서는 순서 근거만 적는다.**
>
> *(2026-07 시점 기록)* 최근 완료: 하드닝 Phase 0~3 5커밋 로컬 main 병합(미push) · 외부 API 3종 실호출 검증(Claude 결함 2건 수정) · **몬스터 도감 24라인 72폼 전량 시드(dex_complete 보상 루프 닫힘, 2026-07-08)** · **OCR 실사진 라이브 검증(손글씨 2장 정확 인식, 2026-07-08)** → 이로써 4종 API 경로 전량 실검증 완료. · **디자인 개편(2026-07-17) 완료** → 남은 것은 실기기 다중 뷰포트 시각 QA(아래 🔵 「브라우저/시스템 테스트」와 동일 범위)뿐.

> **2026-09-04 기준 — 지금은 심사 제출을 향해 간다.** 아래 1~5 는 순서가 의존성으로 묶여 있다.

1. **결함 수정 마무리** *(진행 중)* — 로컬에 11커밋(미push). 여기가 끝나야 2번이 열린다.
2. **🔒 배포 동결 해제** *(→ 배포)* — 푸시 → CI → `kamal deploy`. 검토 전 독후감 공개(`0959ff4`) 등
   실제 결함이 심사 판본에 남지 않게 한다.
3. **📱 배포 후 앱 회귀 확인** *(→ Android)* — 앱으로 학생·교사 핵심 동선을 다시 훑는다.
4. **📱 실기기 검증** *(→ Android, 기기 필요)* — [`DEVICE_VERIFICATION.md`](android/DEVICE_VERIFICATION.md) 의 🔴 부터.
5. **📱 설치 안내문 + 제출 패키지 마감** *(→ Android)*.

> 위 흐름 **밖**에 있는 것(급하지 않음): 🔵 모니터링·에러 트래킹(3.2 착수 판단의 관측 근거),
> CI Android 레인, Active Storage 영속 스토리지.

---

## 남은 작업

### 🔴 배포 (프로덕션 올리기 전 필수)

- [x] **실제 원격 배포** ✅ **완료(2026-08-29)** — `kamal deploy` 로 `chaekgalpi.net` 운영 중. 이 배포에서 `solid_cable`(운영 DB 폴링 pub/sub)·Cloudflare 너머 ActionCable·원격 Path Configuration 이 **처음으로 실검증**됐다(로컬 `cable.yml` 은 `adapter: async` 라 같은 프로세스 안에서만 동작해 검증이 불가능했다).
- [ ] 🔒 **배포 동결 해제 판단** — 심사 판본을 고정하려고 배포를 동결했으나(운영 = `5c3e01b`), 이후 로컬에 **결함 수정 4건 포함 11커밋**이 쌓였다(미push). 특히 `0959ff4`(검토 전 독후감이 우수작으로 공유되던 문제)는 학생 글이 검토 없이 학급을 넘어 공개되던 것이라 심사 판본에 남기기 껄끄럽다. **결함 수정이 끝나면 푸시 → CI → 배포 → 앱 회귀 확인** 순서로 재개한다. 상세는 📱 Android 절.
- [x] **실 도메인 설정** — `config/deploy.yml`의 운영 호스트를 `chaekgalpi.net`·`www.chaekgalpi.net`으로 교체하고 Cloudflare→Kamal 전달 헤더를 활성화함(2026-07-30). 남은 외부 작업: SSL/TLS `Full (strict)`·SSL 발급·실접속 확인.
- [x] **메일러 호스트** — 메일 링크 호스트와 Resend 기본 발신자를 각각 `chaekgalpi.net`, `admin@chaekgalpi.net`으로 통일함(2026-07-30). 남은 외부 작업: Resend DNS 검증 완료 확인.
- [ ] **프로덕션 시크릿 주입** — 서버에 `RAILS_MASTER_KEY`(= `config/master.key` 내용)만 주입하면 credentials 자동 복호화. 절차: [`docs/API_KEYS.md`](docs/API_KEYS.md) §3.2.
- [ ] **Active Storage 프로덕션 스토리지** — 현재 local disk 서비스. 서버 재생성 시 업로드(사진·낭독 녹음) 유실 방지를 위해 DigitalOcean Spaces(S3 호환) 등 영속 스토리지 검토.
- [ ] **SQLite 데이터 영속성** — `storage/production*.sqlite3` 4개 DB(primary/cache/queue/cable)의 kamal 볼륨 마운트·백업 전략 확인.
- [ ] **잡 워커** — 현재 `SOLID_QUEUE_IN_PUMA: true`(Puma 내 실행)로 단일 서버엔 충분. 트래픽 증가 시 전용 job 서버 분리(`deploy.yml`의 `servers.job`).

### 📱 Android 앱 (Hotwire Native — 심사 제출물)

> **코드 개발은 끝났다.** 서명된 release APK 가 검증 4종을 통과했고 단위 테스트 158건·lint 오류 0 이다.
> 남은 것은 **① 실기기 검증 ② 배포 재개 ③ 설치 안내문** 셋이며, ①은 기기가 있어야 하고 ②는
> 위 「배포 동결 해제 판단」에 걸려 있다.

#### 먼저 알아야 할 것 — APK 는 껍데기다

앱은 `https://chaekgalpi.net` 을 여는 WebView 셸이다. **Rails 코드를 고쳐도 APK 를 다시 만들 필요가
없다** — 배포만 하면 앱이 새 화면을 본다. 지금 만들어 둔 APK 와 SHA-256 이 그대로 유효하다.

**예외 — 이럴 때만 Android 를 다시 본다:**

1. **새 다운로드 경로**(CSV·PDF)를 만들 때 → `config/hotwire_native/android_v1.json` 에 규칙 추가.
   이건 **원격 설정이라 APK 재배포 없이** 반영된다. 규칙이 없으면 Turbo 가 파일을 화면 이동으로
   처리해 앱에는 오류만 뜨는데 **서버에는 다운로드 감사 로그가 남는다**(아무도 못 받은 파일이
   내려받아진 것으로 기록됨).
   ⚠️ 링크에 `data-turbo="false"` 를 붙이면 그 훅이 사라져 파일명·MIME 설정을 잃는다(2026-09-03 실측).
2. **앱에서 다르게 동작해야 하는 링크** → 서버 `hotwire_native_app?` 분기.
   WebView 는 `target="_blank"` 를 **무시해서 링크가 아무 일도 하지 않는다**(실측).
3. **패키지명·versionCode/Name·권한·시작 URL** 변경 → 이때만 APK 재빌드.

#### 남은 작업

- [ ] 🔴 **실기기 검증 (Galaxy Tab SM-P610)** — 체크리스트 [`android/DEVICE_VERIFICATION.md`](android/DEVICE_VERIFICATION.md).
  🟢(에뮬레이터 실측 완료) / 🔴(아무도 확인 안 함) / ⚪ 로 나눠 두었으니 **🔴 부터** 하면 된다.
  🔴 는 대부분 에뮬레이터가 신뢰할 수 없는 영역이다 — 실제 카메라, HEIC, 고해상도 사진의 메모리
  압박, **시스템 글자 크기 확대**(초등 전학년 대상이라 화면 매트릭스에서 가장 위험), 파일 관리자를
  통한 설치 경로, One UI WebView. **사진 변형 10종은 절 전체가 🔴** 다.
- [ ] 🔴 **업데이트 설치 확인** — 같은 키로 `versionCode` 2 인 APK 를 한 벌 더 만들어 기기에서 덮어쓴다.
  키가 같아야 업데이트로 설치되므로 **서명 키 확정 후에만** 가능한 검증이다.
- [ ] 🟡 **배포 재개 후 앱 회귀 확인** — 동결 해제·배포 뒤 앱으로 학생·교사 핵심 동선을 다시 훑는다.
  특히 최근 바뀐 **문서 출력·CSV 경로**(위 예외 ①에 해당).
- [ ] 🟡 **`APK_설치_및_체험안내.pdf`** — 아직 없다. `docs/` 의 심사 안내 4종
  (`JUDGE_GUIDE.md`·`JUDGE_MANUAL.html`·`JUDGE_RUN_LOCAL.md`·`소프트웨어_실행안내.md`)에
  **APK·Android 언급이 하나도 없다.** 설치 시나리오는 `DEVICE_VERIFICATION.md` §1 을 재료로 쓴다.
- [ ] 🟡 **제출 패키지 마감** — `~/책갈피_Android_제출/` 에 APK·`SHA256.txt` 준비됨.
  ⚠️ **APK 를 다시 빌드하면 SHA-256 이 바뀌므로 `SHA256.txt` 를 반드시 다시 계산**한다.
  금지 제출물(testOnly·debug APK·미서명·로컬 URL·keystore 포함 zip·서명 후 재압축)은
  [`android/README.md`](android/README.md) §4 참고.

#### 구조적 공백 (P1 — 급하지 않으나 남겨 둔다)

- [ ] **CI 에 Android 레인이 없다** — `.github/workflows/ci.yml` 은 Ruby 잡 5종만 돈다.
  `./gradlew test lintRelease` 가 PR 에서 돌지 않아 **Android 회귀를 로컬에서만 잡는다.**
- [ ] **Espresso instrumentation 테스트 없음** — 의도적 제외(사용자 결정). 덮을 항목(런치·로그인·
  내부이동·뒤로가기·회전 복원·외부 URL·file chooser 취소)은 에뮬레이터 실측으로 기록했고,
  위 CI 공백 때문에 작성해도 자동으로 돌지 않는다. **CI 레인이 생기면 재검토할 것.**
- [ ] **인근 도서관 대출 배지** — 정보나루 상류가 **8초~60초+** 를 오가 배지가 "확인 필요"로 자주
  떨어진다. 화면 속도(0.4초)와 도서관 목록은 백그라운드 워밍 구조로 지켜지므로 P1 이다.
  어떤 타임아웃 값으로도 해결되지 않는 **상류 문제**라 상수 튜닝은 하지 않기로 했다.

#### 서명 키 (2026-09-04 생성)

- 위치 `~/chaekgalpi-release.jks` · alias `chaekgalpi` · 4096-bit RSA · 2056년까지
- 인증서 `CN=Chaekgalpi, O=Chaekgalpi, C=KR` — **요강이 금지하는 시·도명·학교명·출품자명을 넣지
  않았다.** 이 값은 APK 에서 누구나 읽을 수 있고(`apksigner verify --print-certs`) 한 번 만들면
  바꿀 수 없다.
- 지문 `SHA256: D0:C4:10:FD:5C:41:EA:47:8E:56:74:6D:F9:0D:B5:5B:74:C6:84:1F:70:D7:2E:D6:FC:4E:46:FE:79:56:07:61`
- ⚠️ **키와 비밀번호를 잃으면 기존 설치본 위에 업데이트를 올릴 수 없다**(패키지명을 바꾼 새 앱으로
  다시 시작하는 것 외에 방법이 없다). 저장소 밖 2중 백업 필수. `keystore.properties` 는 gitignored.

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
