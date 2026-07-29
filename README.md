# 📖 책갈피 (Chaekgalpi)

> 초등학교 전학년을 위한 **AI 독후감 첨삭 + 반려 몬스터 게이미피케이션** 독서 교육 플랫폼

「책갈피」는 아이들이 스스로 책을 읽고 글을 쓰게 만드는 것을 목표로 하는 교내 독서 플랫폼입니다.
**AI 5축 발전적 첨삭**으로 글쓰기의 질을 높이고, **72폼 반려 몬스터 도감·진화**로 꾸준함을 유도하며,
학생·담임교사·교무관리자·사서·총괄관리자까지 **5개 역할**의 학교 현장 운영을 하나의 앱으로 지원합니다.

- **상태**: 구현 Phase 0~8 완료 · 테스트 1,441 runs / 0 failures · RuboCop(omakase) 무경고 · Brakeman 0
- **외부 연동**: Claude · Gemini(OCR) · 네이버 도서검색 · 정보나루 실연동 검증 완료 (키 없이도 폴백으로 완전 동작)

---

## 목차

- [핵심 기능](#핵심-기능)
- [기술 스택](#기술-스택)
- [빠른 시작](#빠른-시작)
- [외부 API 키](#외부-api-키)
- [사용자 역할](#사용자-역할)
- [테스트 · 품질](#테스트--품질)
- [배포](#배포)
- [프로젝트 구조 · 문서](#프로젝트-구조--문서)
- [출처 및 라이선스](NOTICE.md)

---

## 핵심 기능

### ✍️ 독후감 & AI 5축 첨삭 (핵심 가치)
- **다양한 입력 모드** — 직접 타이핑, **손글씨 사진 → OCR 자동 변환**(Gemini Vision), 음성(STT)·원고지·낭독 녹음 등 접근성(UDL) 입력.
- **AI 5축 첨삭** — Claude가 **내용·감상·삶(과 연결)·구성·맞춤법** 5개 축으로 평가하고 **5축 방사형(radar) 차트**로 시각화. "점수 매기기"가 아닌 **발전적 첨삭**이 설계 철학.
- **고쳐쓰기 & 우수작 공유** — 첨삭을 반영해 다시 쓰고, 잘 쓴 글은 게시판에 공유.
- **AI 진위 확인** — 실제 독서 기반 글인지 보조 판별(suspicion/reasons)로 교사가 확인.
- **무중단 폴백** — AI 호출 실패 시 규칙 기반 첨삭·로컬 캐시로 자동 전환.

### 🐣 게이미피케이션 — 반려 몬스터 도감
- **도감** — 6속성(이야기·지식·감성·모험·자연·상상) × 4계열 = **24 진화 라인**, 각 3단계(기본형→성장형→완전형) = **총 72폼**.
- **스타터 선택 → 마일스톤 발견** — 가챠 없이 레벨업·챌린지·뱃지 등 독서 성취마다 새 몬스터를 발견.
- **진화 시스템** — "포인트 + 독서 행동 조건" 조합. 완전형은 A등급·삶과 연결·고전·고쳐쓰기·도감 완성 등 질 높은 독서 습관을 요구.
- **케어 상점 · 랭킹 · 미션 · 챌린지 · 뱃지 · 레벨/포인트** — 즉각적 피드백 루프.

### 🎮 독서 게임 5종 (교육 다양성 우선)
- `quiz`(독해) · `classic`(고전 읽기) · `vocab`(어휘 낚시=짝짓기) · `whoami`(나는 누구게?=추론) 는 도서를 고르면 즉석에서 문항이 만들어지는 온디맨드 게임(무키·실패 시 오프라인 폴백, 아동 무대기). 결과는 포인트·게이미피케이션과 연동.
- `book`(책 소개 대결) 은 학생이 책 소개를 쓰고 또래가 투표하는 소셜 게임(경계=학급, AI 문항 미호출).

### 📚 콘텐츠 & 커뮤니티
- **도서 검색** — 네이버 도서검색 API(제목·저자·출판사·표지·ISBN), 키 없으면 로컬 카탈로그 폴백.
- **인기 대출 도서** — 정보나루 API 실집계, 실패 시 CSV 임포트.
- **우수작 게시판** — 응원(cheer)·스티커(sticker) 리액션.
- **토론방** — 주제별 토론 게시글.
- **단계 학습 위저드(5단계)** — 진행 상태를 저장하며 완료 시 독후감 초안으로 연결.

---

## 기술 스택

| 영역 | 사용 기술 |
|------|-----------|
| 프레임워크 | Ruby on Rails 8.1 |
| 언어 | Ruby 4.0.5 |
| 데이터베이스 | SQLite (primary / cache / queue / cable 다중 DB) |
| 백그라운드 · 캐시 · 실시간 | Solid Queue · Solid Cache · Solid Cable |
| 프런트엔드 | Hotwire(Turbo · Stimulus) · Import Maps · Propshaft · Tailwind CSS |
| 인가 | Pundit (역할별 접근 권한) |
| 인증 | `has_secure_password` (bcrypt) |
| 외부 HTTP | Faraday (+ faraday-retry) |
| AI | Anthropic Claude (5축 첨삭 · 퀴즈 생성 · 진위 확인) · Google Gemini (손글씨 OCR 전용) |
| 배포 | Docker · Kamal 2 · Thruster (DigitalOcean 대상) |
| 품질 | Minitest · Capybara · RuboCop(omakase) · Brakeman · bundler-audit |

---

## 빠른 시작

### 가장 쉬운 실행 — Docker 한 줄 (권장, 비밀키 불필요)

Ruby·Rails 설치 없이 **Docker Desktop만 있으면** 소스코드를 그대로 실행할 수 있습니다.
개발 모드로 뜨며, 외부 API 키·`master.key` 가 없어도 폴백으로 완전 동작하고 데모 데이터까지 채워집니다.

```bash
docker compose up          # 빌드 + 데모 데이터 적재 + 서버 → http://localhost:3000
```

> Windows 심사위원용 단계별 안내는 [`docs/JUDGE_RUN_LOCAL.md`](docs/JUDGE_RUN_LOCAL.md),
> 체험 계정·둘러보기는 [`docs/JUDGE_GUIDE.md`](docs/JUDGE_GUIDE.md) 참고.
> Windows 에서 Docker 설치조차 자동화하려면 [`windows/setup-and-run.bat`](windows/CLAUDE.md) 더블클릭 한 번으로 WSL2·Ubuntu·Docker 설치부터 실행까지 끝납니다.
> (운영 배포는 `Dockerfile`+Kamal, 심사용 로컬 실행은 `Dockerfile.dev`+`compose.yaml` 로 분리)

### 로컬 개발 요구사항 (Docker 없이 직접 실행 시)
- Ruby **4.0.5** (`.ruby-version` 참고)
- SQLite 3 (2.1 이상)
- (선택) 시스템 테스트용 Chrome/Chromedriver

### 설치 & 실행

```bash
# 1. 의존성 설치 · DB 준비 · 시드를 한 번에
bin/setup

# 2. 개발 서버 실행 (Rails 서버 + Tailwind watch)
bin/dev
```

`bin/setup` 없이 수동으로 진행하려면:

```bash
bundle install
bin/rails db:prepare   # 스키마 생성 + db/seeds.rb 실행
bin/dev
```

앱은 <http://localhost:3000> 에서 뜨고, `/up` 헬스체크가 200이면 정상 부팅입니다.

### 시드로 생성되는 초기 데이터
`bin/rails db:seed`(또는 `db:prepare`)는 다음을 **멱등하게** 적재합니다.

- **총괄관리자 계정** — 이름 `총괄관리자`, 초기 비밀번호 `changeme1234` ⚠️ *운영 전 반드시 변경*
- **학교** — 축소 개발 시드(17개 시도 대표교) · 전량(전국 6,331교)은 후속 적재
- **반려 몬스터 도감** — 24라인 72폼 전량 (`db/seeds/monsters.yml`)
- **뱃지 · 케어/진화 상점 아이템 · 권장도서·고전 카탈로그 · 샘플 퍼블리시 퀴즈**

개별 재적재는 rake 태스크로:

```bash
bin/rails monsters:seed   # 몬스터 도감
bin/rails badges:seed      # 뱃지
bin/rails books:seed       # 도서 카탈로그
bin/rails schools:seed     # 학교
bin/rails quizzes:seed     # 샘플 퀴즈
```

---

## 외부 API 키

앱은 **ENV 환경변수를 우선하고, 없으면 Rails 암호화 credentials 로 폴백**해 키를 읽습니다. **키가 하나도 없어도 앱은 완전히 동작**하며(사진 OCR만 비활성), 각 기능이 폴백 경로로 자동 전환됩니다 — 오프라인 데모가 가능하도록 설계되었습니다.

| credentials 키 | 발급처 | 켜지는 기능 | 폴백 |
|---|---|---|---|
| `claude.api_key` | Google AI Studio | OCR · 5축 첨삭 · 진위 확인 · 퀴즈 생성 | 규칙 기반 첨삭 / 오프라인 퀴즈 (OCR만 비활성) |
| `naver.client_id` · `naver.client_secret` | Naver Developers | 도서 검색(단독 제공자) | 로컬 카탈로그 LIKE 검색 |
| `data4library.api_key` | 정보나루 | 인기대출 동기화 | CSV 업로드 |
| `neis.api_key` | NEIS 교육정보 개방포털 | 학교 스냅샷 갱신(`schools:fetch`) | 커밋된 CSV 오프라인 시드 |

```bash
# 키 편집 (EDITOR 설정 필요)
EDITOR="vim" bin/rails credentials:edit

# 인식 여부 확인
bin/rails runner '
  puts "Claude  : #{Ai::ClaudeClient.available?}"
  puts "도서검색 : #{Books::SearchService.new.available?}"
  puts "정보나루 : #{Library::Data4libraryService.available?}"
'
```

> `config/master.key`(개발) / `RAILS_MASTER_KEY`(프로덕션)로 복호화됩니다. `master.key`는 **절대 커밋하지 마세요**(gitignore 처리됨). 암호문 `config/credentials.yml.enc`는 커밋해도 안전합니다.
>
> 자세한 내용은 [`docs/API_KEYS.md`](docs/API_KEYS.md) 참고.

---

## 사용자 역할

Pundit 정책으로 역할별 접근 권한을 관리하며, 일부 자원은 학교·학급 소속도 확인합니다. 다만 다학교 동시 운영을 전제로 한 앱 전체의 데이터 경계 격리는 검증하지 않았습니다.

| 역할 | 주요 기능 |
|------|-----------|
| **학생** | 독후감 작성·고쳐쓰기·공유, 독서 게임, 몬스터 도감·진화, 랭킹, 커뮤니티 |
| **담임교사** | 검토 목록(모두·미검토·검토완료 필터), 5축 점수 조정·승인·진위 확인, 학생 관리(비번 재설정·포인트 부여), 미션·퀴즈 발행, 루브릭 설정, 문서 출력(표창장·가정통신문·독서 포트폴리오·학급 성장 리포트), CSV 내보내기 |
| **교무관리자** | 전교 통계 + NEIS 생기부 자동 요약 |
| **사서** | 도서관 대시보드, 인기대출(정보나루/CSV), 이달의 책·행사 관리 |
| **총괄관리자(superadmin)** | 전용 `/admin` — 학교·사용자·도서·퀴즈·뱃지·상점·몬스터종 CRUD, 모더레이션, 전역 분석·설정 |

---

## 테스트 · 품질

```bash
bin/rails test          # 모델 · 컨트롤러 · 통합 · 정책 테스트 (1,441 runs)
bin/rails test:system   # 시스템 테스트 (Chrome 필요)
bin/rubocop             # 스타일 (rails-omakase)
bin/brakeman            # 보안 정적 분석
bin/ci                  # 위 검사 일괄 실행 (CI 파이프라인)
```

품질 게이트: 테스트 그린 · RuboCop 무경고 · Brakeman 신규 경고 0 · 마이그레이션 가역성 · 역할별 Pundit 경계 테스트 통과.

---

## 배포

DigitalOcean + Kamal 2 (Docker) 기준입니다.

```bash
kamal setup     # 최초 1회 (서버 프로비저닝 + 첫 배포)
kamal deploy    # 이후 배포
```

배포 전 확인 사항(자세한 내용은 [`TODO.md`](TODO.md) 참고):

- `config/deploy.yml`의 `proxy.host` 를 실제 도메인으로 교체 (현재 플레이스홀더)
- `config/environments/production.rb`의 메일러 `default_url_options` host 교체
- 서버에 `RAILS_MASTER_KEY` 주입 (`.kamal/secrets`가 `config/master.key`에서 처리)
- Active Storage 영속 스토리지 · SQLite 볼륨 마운트/백업 전략 확정
- **`books.isbn` 유니크 인덱스 마이그레이션 배포 전 중복 점검**(아래 드라이런) — 중복이 있으면 인덱스 추가가 실패하므로 배포 전 반드시 1회 확인

### 배포 전 드라이런 — `books.isbn` 중복 점검

`books.isbn` 부분 유니크 인덱스를 도입하는 마이그레이션은 같은 isbn 행이 2개 이상이면 실패합니다. 배포 직전, 운영 서버에서 **읽기 전용**으로 1회 확인하세요(데이터를 변경하지 않습니다).

```bash
# 로컬/서버 콘솔에서 실행 (읽기 전용)
bin/rails runner 'd = Book.where.not(isbn: [nil, ""]).group(:isbn).having("COUNT(*) > 1").count; puts d.empty? ? "✅ 중복 isbn 0건 — 유니크 인덱스 배포 안전" : "⚠️ 중복 isbn #{d.size}건: #{d.inspect} (인덱스 추가 전 정리 필요)"'

# Kamal 운영 서버에서 원격 실행
kamal app exec -i 'bin/rails runner "d = Book.where.not(isbn: [nil, %q()]).group(:isbn).having(%q(COUNT(*) > 1)).count; puts d.empty? ? %q(OK: 중복 0건) : %Q(WARN: 중복 #{d.size}건 #{d.inspect})"'
```

`✅ 중복 0건`이면 그대로 배포합니다. 중복이 나오면(정상 운영 시 발생하지 않아야 함) 인덱스 추가 전에 중복 행 정리가 필요합니다.

---

## 프로젝트 구조 · 문서

```
app/
  controllers/   역할별 네임스페이스 (teacher · librarian · school_admin · admin · games)
  models/        report · book · monster_species · user_monster · quiz · badge · school ...
  services/      ai/ (claude_client · ocr · review · verify · quiz_draft)
                 books/ · library/ · monster_acquisition · ranking_board · reading_stats
  jobs/          ai_review_job · ocr_job (백그라운드 첨삭·OCR)
db/seeds/        monsters.yml (24라인 72폼)
lib/tasks/       monsters · badges · books · schools · quizzes rake 시드
docs/            설계·구현·운영 문서 (아래)
```

| 문서 | 내용 |
|------|------|
| [`DESIGN.md`](DESIGN.md) | 「책갈피」 디자인 시스템(토큰·컴포넌트·타이포·반응형) |
| [`docs/CLOUD_DEPLOYMENT_COMPARISON.md`](docs/CLOUD_DEPLOYMENT_COMPARISON.md) | DigitalOcean·NAVER Cloud·AWS·Oracle 배포 및 메일러 비교 |
| [`docs/monsters.md`](docs/monsters.md) | 반려 몬스터 도감 시드 설계 + AI 이미지 생성 가이드 |
| [`docs/API_KEYS.md`](docs/API_KEYS.md) | 외부 API 키 주입·폴백 가이드 |
| [`NOTICE.md`](NOTICE.md) | 폰트·이미지·데이터·AI 모델 출처 및 라이선스 표기 |
| [`TODO.md`](TODO.md) | 남은 작업(배포·에셋·모니터링) |
</content>
</invoke>
