# 💻 소스코드 직접 실행 안내 (Windows 심사위원용)

제출된 「책갈피」 소스코드를 심사위원 PC(Windows 10/11)에서 **직접 실행**하는 방법입니다.
두 가지 방법이 있으나, **방법 A(Docker)** 를 강력히 권장합니다 — 명령어 **한 줄**로 끝나고,
Ruby·Rails·Linux 사전 지식이 필요 없습니다.

> ℹ️ 이 앱은 **비밀키·외부 API 키가 없어도** 완전히 동작하도록 설계되어 있습니다.
> (AI 첨삭 등은 자동으로 규칙기반 폴백으로 대체됩니다.) 별도 키 입력이 필요 없습니다.

---

## ✅ 방법 A — Docker Desktop (권장, 한 줄 실행)

### 1) Docker Desktop 설치 (최초 1회)
- https://www.docker.com/products/docker-desktop/ 에서 **Windows용**을 내려받아 설치합니다.
- 설치 중 "Use WSL 2 based engine" 옵션은 켜 둔 채 진행하고, 안내에 따라 **재부팅**합니다.
  (Windows가 WSL2를 자동으로 설정합니다. Windows Home 에디션도 지원됩니다.)
- 설치 후 **Docker Desktop을 실행**하고, 좌측 하단 고래 아이콘이 초록색(실행 중)이 될 때까지 기다립니다.

### 2) 소스코드 압축 풀기
- 제출된 소스 zip을 원하는 폴더(예: `C:\chaekgalpi`)에 풉니다.

### 3) 그 폴더에서 명령창 열기
- 압축을 푼 폴더를 파일 탐색기로 연 뒤, **주소창에 `cmd` 를 입력하고 Enter** 를 누릅니다.
  (그 폴더 위치에서 명령 프롬프트가 열립니다. PowerShell도 무방합니다.)

### 4) 한 줄 실행
```bat
docker compose up
```
- **최초 1회는** 이미지 빌드 + 데이터(도서 8,500여 권·데모 학급) 적재로 **수 분~십수 분** 걸립니다.
  (인터넷 연결 필요 — 최초 빌드 때 구성요소를 내려받습니다.)
- 아래 메시지가 보이면 준비 완료입니다:
  ```
  ✅ 준비 완료!  브라우저에서 아래 주소를 여세요:
        👉  http://localhost:3000
  ```

### 5) 브라우저로 접속
- 크롬·엣지 등에서 **http://localhost:3000** 을 엽니다.

### 6) 로그인
- 계정과 둘러보기 코스는 **[`JUDGE_GUIDE.md`](JUDGE_GUIDE.md)** 를 그대로 사용하세요.
  (학생 `student1234`, 담임 `teacher1234` 등 동일)
- **이 로컬 실행에서 총괄관리자 계정**은 아래와 같습니다(비밀키가 없어 기본값 사용):
  - 이메일 `admin@example.com` / 비밀번호 **`changeme1234`**

### 7) 종료 / 초기화
```bat
Ctrl + C            :: 서버 정지 (명령창에서)
docker compose down :: 컨테이너 정리 (데이터는 보존 → 다음 실행이 빠름)

docker compose down -v   :: 데이터까지 완전 삭제(초기화)
docker compose up        :: 다시 처음부터
```

> 💡 최소 사양 권장: RAM 8GB 이상, 디스크 여유 수 GB. 최초 실행만 느리고, 두 번째부터는 빠릅니다.

---

## 🔑 (참고) Docker 실행에서 실제 API 키·Credentials는 적용되나요?

**기본값은 "적용 안 됨"이며, 그래도 앱은 완전히 동작합니다.** 이유와 옵션은 다음과 같습니다.

- 앱 키는 `RAILS_MASTER_KEY`(→ 암호화된 `config/credentials.yml.enc` 복호화)로 읽습니다.
  그런데 이 실행 세트는 보안을 위해 **`master.key` 를 이미지에 넣지 않습니다**(`.dockerignore` 제외).
  따라서 **credentials 가 복호화되지 않아** Gemini·네이버·정보나루가 **자동으로 규칙기반/로컬 폴백**으로 동작합니다.
- 심사위원에게 이 편이 **안전**합니다: `master.key` 는 실제(유료) API 키를 여는 비밀이므로 배포·제출물에 절대 포함하면 안 됩니다.
- **중요**: 시드된 **데모 독후감에는 이미 AI 5축 첨삭 결과(방사형 차트·칭찬/보완/성장 피드백)가 저장**되어 있어,
  기존 데이터를 열어보면 실제 키가 없어도 AI 첨삭 화면을 그대로 확인할 수 있습니다. (라이브로 *새* 글을 쓸 때만 폴백 첨삭이 적용됩니다.)

### 운영자가 실제 API를 켜고 싶다면 (심사위원 배포 X, 본인 시연용)
`compose.override.yaml` 파일을 만들면 `docker compose up` 이 자동 병합합니다(이 파일은 git 에 커밋되지 않도록 무시 처리됨).

- **방법 ①(권장·안전) — 개별 키만 주입** (마스터키 불필요, 넣은 키만 켜짐):
  ```yaml
  # compose.override.yaml
  services:
    app:
      environment:
        GEMINI_API_KEY: "실제-Gemini-키"
        NAVER_CLIENT_ID: "..."
        NAVER_CLIENT_SECRET: "..."
  ```
- **방법 ②— 마스터키로 커밋된 credentials 전체 해제** (credentials 에 든 실제 키가 모두 켜짐):
  ```yaml
  # compose.override.yaml
  services:
    app:
      environment:
        RAILS_MASTER_KEY: "config/master.key 파일의 내용"
  ```
  > ⚠️ 이 방법은 실제 키를 활성화합니다. 심사위원에게 주는 배포/제출물에는 쓰지 마세요.

---

## 🐧 방법 B — WSL2 + Ruby 직접 설치 (참고, 리눅스 경험자용)

Docker 없이 리눅스 환경에서 직접 빌드하려는 경우입니다. **단계가 많고 실패 지점(루비 컴파일·네이티브
확장)이 있어** 비전문가에게는 권장하지 않습니다.

```powershell
:: (관리자 PowerShell) WSL2 + Ubuntu 설치 후 재부팅
wsl --install
```
재부팅 후 Ubuntu 터미널에서:
```bash
# 1) 시스템 라이브러리
sudo apt update && sudo apt install -y build-essential git libyaml-dev libvips sqlite3 libsqlite3-dev curl

# 2) mise 설치 후 Ruby 4.0.5 (컴파일 — 수 분)
curl https://mise.run | sh
echo 'eval "$(~/.local/bin/mise activate bash)"' >> ~/.bashrc && source ~/.bashrc

# 3) 소스 폴더로 이동 (Windows 드라이브는 /mnt/c/... )
cd /mnt/c/chaekgalpi
mise install          # .ruby-version(4.0.5) 자동 설치
gem install bundler
bundle install

# 4) DB 준비 + 데모 데이터
bin/rails db:prepare
SEED_DEMO=1 bin/rails db:seed

# 5) 실행 → http://localhost:3000
bin/dev
```
이 방법의 총괄관리자 계정도 `admin@example.com` / `changeme1234` 입니다(비밀키 미사용 시).

---

## ❓ 자주 겪는 문제

| 증상 | 해결 |
|------|------|
| `docker` 명령을 못 찾음 | Docker Desktop이 **실행 중**인지 확인(고래 아이콘 초록). 명령창을 새로 여세요. |
| `port is already allocated` (3000 사용 중) | 다른 프로그램이 3000 포트를 씀. 그 프로그램을 끄거나, `compose.yaml`의 `"3000:3000"`을 `"3001:3000"`으로 바꾼 뒤 http://localhost:3001 접속. |
| 최초 실행이 오래 걸림 | 정상입니다(빌드+데이터 적재). 명령창 로그가 흐르면 진행 중입니다. |
| 화면이 안 뜸 | "✅ 준비 완료" 메시지가 나온 뒤에 http://localhost:3000 을 여세요. |
| AI 첨삭이 단순해 보임 | 의도된 동작입니다. 키 없이 규칙기반 폴백으로 5축·차트가 표시됩니다. |

---
> 온라인 데모(서버 배포) 방식은 [`DEMO_DEPLOYMENT.md`](DEMO_DEPLOYMENT.md), 체험 계정·둘러보기는 [`JUDGE_GUIDE.md`](JUDGE_GUIDE.md) 참고.
