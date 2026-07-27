# 심사·시연용 배포 런북 (DigitalOcean + Kamal)

> **목적**: 교육 정보화 연구대회 심사위원(대개 Windows 10/11, Ruby·Rails·Linux 미경험)이
> **소스코드를 직접 실행하지 않고 URL 클릭만으로** 「책갈피」를 체험할 수 있도록,
> 데모 데이터가 가득 찬 인스턴스를 인터넷에 하나 띄우는 절차입니다.
>
> 이 문서는 **운영자(출품 교사)용**입니다. 심사위원에게 건네는 안내문은
> [`JUDGE_GUIDE.md`](JUDGE_GUIDE.md) 를 쓰세요.

핵심 특징
- 앱은 **`RAILS_MASTER_KEY` 하나**만 있으면 외부 API 키(Gemini·네이버·정보나루) 없이도 완전 동작합니다(폴백). 심사 데모에 키를 넣을 필요가 없습니다.
- **`DEMO_DEPLOYMENT=1`** 로 시드하면 production 에서도 5개 역할 계정과 39개 학급 분량의 "많이 써 본 것 같은" 데모 데이터가 적재됩니다(평소 운영 배포에는 유입되지 않음).

---

## 0. 준비물 체크리스트

| 항목 | 설명 | 비용 |
|------|------|------|
| DigitalOcean 계정 | 배포 대상 서버(Droplet) 생성 | 신규 가입 시 크레딧 제공되는 경우 있음 |
| Droplet 1대 | Ubuntu, 최소 **2GB RAM / 1vCPU**(권장 2GB↑ — 데모 시드가 무겁습니다) | 월 $12 수준(2GB), 심사 기간만 켜면 일할 |
| 도메인 1개 | HTTPS(Let's Encrypt) 자동 발급에 **필수** | 유료 도메인 연 1만원대 **또는** 무료 서브도메인(아래 팁) |
| 로컬 PC | 이 저장소 + Docker + Kamal 설치. 배포 명령은 여기서 실행 | - |
| `config/master.key` | 로컬에 존재해야 함(커밋 금지 파일). 서버 시크릿의 유일한 소스 | - |

> 💡 **무료 도메인 팁**: 도메인을 사기 싫으면 [DuckDNS](https://www.duckdns.org) 같은 무료 서비스로
> `책갈피데모.duckdns.org` 처럼 서브도메인을 만들고 A 레코드를 Droplet IP 로 지정하면 됩니다.
> Let's Encrypt 는 이런 서브도메인에도 인증서를 발급합니다.

로컬 도구 설치(최초 1회):
```bash
gem install kamal          # 저장소 bin/kamal 로도 실행 가능
docker --version           # Docker Desktop 또는 Docker Engine 필요(이미지 빌드용)
```

---

## 1. 배포 설정 3곳 수정

배포 전에 플레이스홀더를 **본인 값**으로 바꿉니다.

### ① `config/deploy.yml`
```yaml
servers:
  web:
    - 203.0.113.10          # ← 본인 Droplet 공인 IP

proxy:
  ssl: true
  host: chaekgalpi-demo.duckdns.org   # ← 본인 도메인(위에서 A레코드로 IP에 연결한 그 도메인)
```

### ② `config/environments/production.rb` (80번째 줄 근처)
```ruby
config.action_mailer.default_url_options = { host: "chaekgalpi-demo.duckdns.org" }  # ← 같은 도메인
```
> 데모에서 메일 발송 기능은 쓰지 않으므로 값이 틀려도 크래시는 없지만, 링크 생성 일관성을 위해 맞춰 둡니다.

### ③ 도메인 A 레코드 연결 (배포 **전에** 미리)
DNS 관리 화면에서 위 `host` 도메인의 **A 레코드**를 Droplet 공인 IP 로 지정합니다.
Let's Encrypt 인증서 발급이 이 DNS 연결에 의존하므로, 전파(수 분~수십 분)를 기다린 뒤 다음 단계로 갑니다.

---

## 2. 사전 점검(선택이지만 권장)

`books.isbn` 유니크 인덱스 마이그레이션이 중복 ISBN 이 있으면 실패합니다. 로컬에서 읽기 전용으로 1회 확인:
```bash
bin/rails runner 'd = Book.where.not(isbn: [nil, ""]).group(:isbn).having("COUNT(*) > 1").count; puts d.empty? ? "✅ 중복 isbn 0건 — 배포 안전" : "⚠️ 중복 #{d.size}건: #{d.inspect}"'
```
`✅` 면 그대로 진행합니다.

---

## 3. 최초 배포 (`kamal setup`)

로컬 저장소 루트에서:
```bash
bin/kamal setup
```
이 명령이 하는 일:
1. Droplet 에 Docker 설치 · Kamal 프록시 기동
2. 로컬에서 이미지 빌드 → 서버로 전송
3. 컨테이너 기동. 진입점(`bin/docker-entrypoint`)이 자동으로 `db:prepare` 실행
   → 스키마 생성 + **기본 시드**(전국 학교 6,333교·도서 8,502권·몬스터 72폼·총괄관리자) 적재
4. Let's Encrypt 로 HTTPS 인증서 발급(도메인 A 레코드가 맞아야 성공)

> ⏱️ 기본 시드(도서 8,502권 등)까지 도는 첫 부팅은 수 분 걸릴 수 있습니다. 로그 확인:
> ```bash
> bin/kamal app logs -f
> ```

여기까지 하면 앱은 뜨지만 **아직 데모 데이터·역할 계정은 없습니다**(다음 단계).

---

## 4. 심사용 데이터 적재 (핵심 단계 — 빼먹지 말 것)

`DEMO_DEPLOYMENT=1` 로 시드해야 심사위원이 로그인할 **5개 역할 계정**과 **39개 학급 분량의 활동 데이터**(독후감·게임·몬스터·랭킹·미션·커뮤니티)가 만들어집니다.

서버 컨테이너 안에서 실행합니다(같은 SQLite 볼륨에 적재):
```bash
# 컨테이너 셸 진입 (deploy.yml 의 alias)
bin/kamal shell

# ── 컨테이너 내부 프롬프트에서 ──
DEMO_DEPLOYMENT=1 bin/rails db:seed
# 완료되면(수 분 소요) exit
exit
```

> 한 줄로 하려면(셸 진입 없이):
> ```bash
> bin/kamal app exec "env DEMO_DEPLOYMENT=1 bin/rails db:seed"
> ```
> `db:seed` 는 **멱등**이라 여러 번 실행해도 안전합니다(중복 생성 없음).

### 4-1. 총괄관리자 데모 비밀번호 설정
총괄관리자(superadmin) 비밀번호는 암호화 credentials 값이라 문서에 적을 수 없습니다.
심사용으로 **알려진 비밀번호**를 지정합니다. 컨테이너 셸(또는 `bin/kamal console`)에서:
```bash
bin/kamal shell
# ── 컨테이너 내부 ──
bin/rails runner 'u = User.find_by(email: "admin@example.com"); u.update!(password: "chaekgalpi-demo-2026"); puts "총괄관리자 로그인 → #{u.email} / chaekgalpi-demo-2026"'
exit
```
(원하는 비밀번호로 바꿔도 됩니다. 이 값을 [`JUDGE_GUIDE.md`](JUDGE_GUIDE.md) 총괄관리자 칸에 기입하세요.)

---

## 5. 접속 확인

브라우저에서:
- `https://<도메인>/up` → **200 OK / 초록 화면** 이면 정상 부팅
- `https://<도메인>` → 로그인 안내 화면

[`JUDGE_GUIDE.md`](JUDGE_GUIDE.md) 의 계정으로 각 역할 로그인이 되는지 **심사 전에 반드시 리허설**하세요:
- 학생(튜플 로그인: 학교→학년도→학급→이름→비번), 담임교사(이메일), 교무관리자, 사서, 총괄관리자

---

## 6. 심사 중 데이터 초기화(필요 시)

심사위원이 데이터를 어질러 놓았을 때 깨끗한 데모 상태로 되돌리려면:
```bash
bin/kamal shell
# ── 컨테이너 내부 ──
bin/rails db:reset            # ⚠️ DB 전체 삭제 후 재생성 (production 에선 DISABLE_DATABASE_ENVIRONMENT_CHECK 필요할 수 있음)
DEMO_DEPLOYMENT=1 bin/rails db:seed
exit
```
> 더 안전하게는, 심사 시작 전 볼륨을 백업해 두고 문제가 생기면 복원하는 방법도 있습니다.
> 소규모 심사(심사위원 수 명)라면 보통 초기화 없이도 충분합니다.

---

## 7. 심사 종료 후 정리 (비용 절감)

심사 기간이 끝나면 반드시 자원을 내려 과금을 멈춥니다.
```bash
bin/kamal remove             # 컨테이너·프록시·이미지 정리
```
그리고 **DigitalOcean 대시보드에서 Droplet 을 Destroy** 합니다(Droplet 이 살아있으면 계속 과금됩니다).
도메인이 유료였다면 자동갱신을 끄세요.

> 💰 **비용 요약**: 2GB Droplet 기준 월 $12 수준. 심사 기간(예: 1~2주)만 켜면 **몇 천 원~1만 원대**로 끝납니다.
> DigitalOcean 은 시간당 과금이라 쓴 만큼만 냅니다.

---

## 8. 트러블슈팅

| 증상 | 원인/해결 |
|------|-----------|
| `kamal setup` 이 SSL 단계에서 멈춤/실패 | 도메인 A 레코드가 아직 전파 안 됨. DNS 확인(`nslookup <도메인>`) 후 재시도. |
| `/up` 이 502/503 | 첫 부팅 시드가 아직 진행 중일 수 있음. `bin/kamal app logs -f` 로 확인 후 대기. |
| 심사위원이 빈 앱을 봄 / 로그인 계정 없음 | **4단계(`DEMO_DEPLOYMENT=1` 시드)를 안 했음.** 4단계 실행. |
| 학생 로그인이 안 됨 | 학생은 **이메일이 아니라** 학교·학년도·학급·이름·비번 튜플 로그인. `JUDGE_GUIDE.md` 의 정확한 값 사용. |
| 이미지 빌드 arch 오류 | `config/deploy.yml` 의 `builder.arch: amd64` 는 일반 Droplet(amd64) 기준. ARM Droplet 이면 `arm64` 로. |
| 배포는 됐는데 표지 이미지가 안 뜸 | 혼합 콘텐츠(http 표지) 문제는 시드 백필로 https 승격됨. 새로 검색 등록된 도서만 간헐 발생 가능(데모 영향 미미). |

---

## 부록 A. 대안 — 소스코드 제출 패키지(실행 안 하는 심사위원용)

온라인 데모와 **별개로**, 소스코드 zip 도 함께 제출합니다. 심사위원이 실행하지 않아도 되도록:

1. **변경사항을 먼저 커밋**하세요(시드 데이터 `db/seeds/**` 는 이제 git 에 추적됩니다 — 과거 무시 규칙 제거).
   그런 다음 정리 압축:
   ```bash
   git archive --format=zip --output=../chaekgalpi_source.zip HEAD
   ```
   `git archive` 는 **커밋된 것만** 담고 `.gitignore` 대상(`storage/`·`log/`·`tmp/`·`config/master.key`)을 자동 제외합니다.
   시드 데이터를 추적으로 바꿨으므로 학교·도서·데모가 zip 에 포함되어 심사위원이 실행하면 데이터가 채워집니다.
   **`config/master.key` 는 절대 포함되지 않습니다**(gitignore 로 제외 — 암호문 `credentials.yml.enc` 만 포함되며 키 없이는 복호화 불가라 안전).

   > ⚠️ 커밋하지 않은 상태로 zip 을 만들면 `git archive HEAD` 는 최신 변경(시드 포함)을 빠뜨립니다. 반드시 커밋 후 실행하세요.
   > (커밋이 어렵다면 작업트리 전체를 압축하되 `-x '.git/*' -x 'config/master.key' -x 'storage/*' -x 'log/*' -x 'tmp/*' -x 'script/.venv/*'` 로 제외.)
2. zip 최상단 `README.md` 가 실행법·구조·데모 URL 을 안내합니다. 제출 설명서에 **"실행 불필요 — 온라인 데모/영상 참고"** 를 명시하세요.
3. 함께 넣을 것: [`JUDGE_GUIDE.md`](JUDGE_GUIDE.md)(접속 안내), 시연 영상 링크(있으면), 연구보고서.

## 부록 B. 배포 없이 로컬 시연만 할 경우

발표장에서 본인 노트북(개발 환경)으로 직접 시연한다면 배포 없이:
```bash
SEED_DEMO=1 bin/rails db:seed   # 데모 데이터 적재(개발 환경)
bin/dev                          # http://localhost:3000
```
이 경우엔 `DEMO_DEPLOYMENT` 대신 기존 `SEED_DEMO=1` 을 씁니다(개발 환경 전용).

---
> 관련 문서: [`../README.md`](../README.md) · [`CLOUD_DEPLOYMENT_COMPARISON.md`](CLOUD_DEPLOYMENT_COMPARISON.md) · [`API_KEYS.md`](API_KEYS.md) · [`JUDGE_GUIDE.md`](JUDGE_GUIDE.md)
