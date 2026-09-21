# 📖 책갈피 (Chaekgalpi)

> 초등학교 전학년을 위한 **AI 독후감 첨삭 + 반려 몬스터 게이미피케이션** 독서 교육 플랫폼

「책갈피」는 아이들이 스스로 책을 읽고 글을 쓰게 만드는 것을 목표로 하는 교내 독서 플랫폼입니다.
**AI 5축 발전적 첨삭**으로 글쓰기의 질을 높이고, **72폼 반려 몬스터 도감·진화**로 꾸준함을 유도하며,
학생·담임교사·교무관리자·사서·총괄관리자까지 **5개 역할**의 학교 현장 운영을 하나의 앱으로 지원합니다.

- **외부 연동**: Claude(첨삭·OCR) · 네이버 도서검색 · 정보나루 실연동 검증 완료 (키 없이도 폴백으로 완전 동작)

---

## 목차

- [핵심 기능](#핵심-기능)
- [기술 스택](#기술-스택)
- [Android 앱](#android-앱)
- [서버 환경 설정](#서버-환경-설정)
- [서버 빠른 시작](#서버-빠른-시작)
- [외부 API 키](#외부-api-키)
- [사용자 역할](#사용자-역할)
- [테스트 · 품질](#테스트--품질)
- [프로젝트 구조 · 문서](#프로젝트-구조--문서)
- [출처 및 라이선스](NOTICE.md)

---

## 핵심 기능

### ✍️ 독후감 & AI 5축 첨삭 (핵심 가치)
- **다양한 입력 모드** — 직접 타이핑, 단계 학습으로 쓰기, **손글씨 사진 → OCR 자동 변환**(Claude Vision).
- **AI 5축 첨삭** — Claude가 **내용·감상·삶(과 연결)·구성·맞춤법** 5개 축으로 평가하고 **5축 방사형(radar) 차트**로 시각화. "점수 매기기"가 아닌 **발전적 첨삭**이 설계 철학.
- **고쳐쓰기 & 우수작 공유** — 첨삭을 반영해 다시 쓰고, 잘 쓴 글은 게시판에 공유.
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

| 영역                       | 사용 기술                                                                       |
| -------------------------- | ------------------------------------------------------------------------------- |
| 프레임워크                 | Ruby on Rails 8.1                                                               |
| 언어                       | Ruby 4.0.5                                                                      |
| 데이터베이스               | SQLite (primary / cache / queue / cable 다중 DB)                                |
| 백그라운드 · 캐시 · 실시간 | Solid Queue · Solid Cache · Solid Cable                                         |
| 프런트엔드                 | Hotwire(Turbo · Stimulus) · Import Maps · Propshaft · Tailwind CSS              |
| 인가                       | Pundit (역할별 접근 권한)                                                       |
| 인증                       | `has_secure_password` (bcrypt)                                                  |
| 외부 HTTP                  | Faraday (+ faraday-retry)                                                       |
| AI                         | Anthropic Claude (5축 첨삭 · 퀴즈 생성 · 손글씨 OCR)                            |
| Android                    | Hotwire Native 1.3.1 · Kotlin 2.3 · AGP 8.13 · minSdk 28 (**웹앱과 동시 운영**) |
| 배포                       | Docker · Kamal 2 · Thruster (NHN 클라우드 대상)                                 |
| 품질                       | Minitest · Capybara · RuboCop(omakase) · Brakeman · bundler-audit               |

---

## Android 앱

같은 Rails 화면과 세션을 **공유 WebView 로 재사용**하는 Hotwire Native 셸이다. 웹앱과 동시에
운영되며, 서버는 하나다 — 앱 전용 API 도 앱 전용 화면 사본도 없다.

```bash
cd android
./gradlew test lintRelease          # 단위 테스트 158건 + lint
./gradlew assembleDebug             # 에뮬레이터용 (기본 http://10.0.2.2:3000)
./gradlew assembleRelease           # 실제 서명 키 필요
```

- **웹 무영향이 최우선 원칙**이다. 앱 전용 동작은 `hotwire_native_app?`(서버) 와
  `BridgeComponent.shouldLoad`(클라이언트) 뒤에만 둔다 — 일반 브라우저에서는 브리지 컨트롤러가
  **아예 로드되지 않아** 기존 폴백(`<a download>`·인라인 `window.print()`)이 그대로 남는다.
- **release 빌드 가드 2종**: 시작 URL 이 `https://chaekgalpi.net` 이 아니면(http·타 호스트·
  포트·userinfo·접미사 공격) 빌드가 실패하고, 서명 키가 없거나 경로가 비었으면 **debug 키로
  폴백하지 않고** 실패한다.
- 화면 규칙(어느 경로를 어떻게 열지·무엇을 다운로드로 볼지)의 단일 진실은
  `config/hotwire_native/android_v1.json` 이고 앱이 `GET /configurations/android_v1.json` 으로
  받아 간다 — **APK 재배포 없이** 규칙을 바꿀 수 있다.

자세한 것은 [`android/README.md`](android/README.md)(빌드·서명·versionCode 정책) ·
[`android/DEVICE_VERIFICATION.md`](android/DEVICE_VERIFICATION.md)(실기기 검증 체크리스트).

---

## 서버 환경 설정

**Docker 로만 실행할 거라면 Docker 하나면 충분**하므로 이 절을 건너뛰고 [서버 빠른 시작](#서버-빠른-시작) 으로
가세요. 아래는 Ruby 를 설치해 **소스로 직접 실행**(코드 수정·테스트)할 때의 준비입니다.

- **Windows** → WSL2 로 Ubuntu 를 켜고, **그 안에서 Linux 와 똑같이** 진행합니다.
- **Linux · macOS** → 루트의 [`setup.sh`](setup.sh) 한 번이면 끝납니다.

### Windows

Windows 에 Ruby 를 직접 설치하지 않습니다. 마이크로소프트 공식 기능인 **WSL2** 로 Ubuntu 를
설치하고, 그 Ubuntu 터미널에서 [Linux · macOS](#linux--macos) 절을 그대로 따르면 됩니다.
`.bat`·`.ps1` 파일을 하나도 쓰지 않으므로 Windows 11 스마트 앱 컨트롤에 걸릴 것도 없습니다.

<details>
<summary><b>관리자 PowerShell 여는 법</b> (처음이신 분만 펼쳐 보세요)</summary>

1. 키보드의 `Windows 키` 를 누르고 `powershell` 이라고 입력합니다.
2. 검색 결과의 **Windows PowerShell** 에 **마우스 오른쪽 클릭 → [관리자 권한으로 실행]**.
3. "이 앱이 디바이스를 변경할 수 있도록 허용하시겠어요?" 창이 뜨면 **[예]**.
4. 파란 창이 열리면 아래 명령을 붙여넣고 `Enter` 를 누릅니다. (붙여넣기는 `Ctrl+V` 또는 마우스 오른쪽 클릭)

</details>

**1) WSL2 + Ubuntu 설치** — 최초 1회, 5~10분. 관리자 PowerShell 에서:

```powershell
wsl --install -d Ubuntu
```

- 도중에 검은 Ubuntu 창이 열리면 안내에 따라 **사용자 이름과 암호를 한 번 만들고** 그 창을 닫습니다.
- 끝나면 **PC 를 한 번 다시 시작**합니다. 이미 WSL 이 깔린 PC 라면 "이미 설치되어 있습니다" 만 뜹니다 — 정상입니다.
- 이후에는 시작 메뉴에서 **Ubuntu** 를 열면 리눅스 터미널이 뜹니다. **여기서부터 모든 명령은 이 Ubuntu 터미널**에서 칩니다.

**2) 소스를 리눅스 쪽으로 옮기기** — Ubuntu 터미널에서:

```bash
cp -r /mnt/c/Users/<윈도우_사용자명>/Downloads/chaekgalpi ~/chaekgalpi   # 압축을 푼 소스 폴더
cd ~/chaekgalpi
```

- 윈도우 디스크는 Ubuntu 안에서 `/mnt/c/...` 로 보입니다. 그 자리에서 바로 돌려도 되지만,
  WSL 파일시스템(`~/`)으로 옮기면 SQLite·파일 입출력이 몇 배 빨라집니다.
- `git clone <저장소 주소> ~/chaekgalpi` 로 받아도 됩니다.

**3) 이제부터는 Linux 와 같습니다** — 바로 아래 [Linux · macOS](#linux--macos) 의 `./setup.sh` 를 실행하세요.

| 증상                                    | 해결                                                                                        |
| --------------------------------------- | ------------------------------------------------------------------------------------------- |
| `wsl : 이 용어가 ... 인식되지 않습니다` | Windows 10 2004(빌드 19041) 미만입니다. Windows 업데이트 후 다시 시도하세요.                |
| 설치 중 가상화 관련 오류                | PC 의 BIOS/UEFI 에서 가상화(VT-x / AMD-V)를 켜야 합니다.                                    |
| Ubuntu 창이 열리자마자 닫힘             | 관리자 PowerShell 에서 `wsl --shutdown` 을 실행한 뒤 시작 메뉴의 **Ubuntu** 를 다시 엽니다. |

### Linux · macOS

소스 폴더에서 한 줄입니다. Ubuntu·Debian·Fedora·Arch 계열과 macOS(Apple Silicon·Intel), WSL2 Ubuntu 에서 동작합니다.

```bash
cd chaekgalpi        # compose.yaml 이 보이는 소스 폴더
./setup.sh           # 시스템 패키지 → mise → Ruby 4.0.5 → 젬 → DB·시드 (최초 5~10분)
```

`setup.sh` 가 순서대로 하는 일입니다. 이미 있는 것은 건너뛰므로 **몇 번을 다시 실행해도 안전**합니다.

| 단계            | 하는 일                                                                                                                                                                                                          |
| --------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1 시스템 패키지 | `apt`/`dnf`/`pacman`/`brew` 로 C 컴파일러·`git`·`curl`·`pkg-config`·`libyaml`·`sqlite3`·`libvips` 설치(`Dockerfile.dev` 와 같은 목록). `sudo` 암호를 한 번 묻습니다.                                             |
| 2 mise          | Ruby 버전 관리자 [mise](https://mise.jdx.dev) 를 `~/.local/bin`(macOS 는 Homebrew)에 설치하고 `~/.bashrc`(또는 `.zshrc`)에 `mise activate` 한 줄 추가                                                            |
| 3 Ruby          | mise 가 [`.ruby-version`](.ruby-version)(`ruby-4.0.5`)을 읽도록 설정하고, **미리 컴파일된(precompiled) 바이너리**로 Ruby 4.0.5 설치 — 소스 빌드가 없어 수십 초면 끝나고 OpenSSL 같은 빌드 의존성도 필요 없습니다 |
| 4 앱            | `foreman` 설치 → [`bin/setup`](bin/setup)(`bundle install` → `db:prepare` 스키마·시드 → 로그 정리)                                                                                                               |

| 옵션                         | 뜻                                                                       |
| ---------------------------- | ------------------------------------------------------------------------ |
| `./setup.sh --run`           | 준비가 끝나면 그대로 `bin/dev` 로 서버까지 띄웁니다                      |
| `./setup.sh --skip-packages` | 1단계(시스템 패키지)를 건너뜁니다 — 이미 갖춰져 있거나 `sudo` 가 없을 때 |
| `./setup.sh --dry-run`       | 실행하지 않고 할 일만 출력합니다                                         |

끝나면 **새 터미널을 열거나 `exec $SHELL -l`** 로 셸을 다시 읽고 `bin/dev` 를 실행하세요 → <http://localhost:3000>.

<details>
<summary><b>손으로 직접 하려면</b> (setup.sh 가 하는 일 그대로)</summary>

#### Linux (Ubuntu · Debian)

```bash
# 1) 시스템 패키지 — Dockerfile.dev 와 같은 목록
sudo apt-get update
sudo apt-get install -y build-essential git curl pkg-config libyaml-dev sqlite3 libsqlite3-dev libvips

# 2) mise — Ruby 버전 관리자
curl https://mise.run | sh
echo 'eval "$(~/.local/bin/mise activate bash)"' >> ~/.bashrc     # zsh 면 bash→zsh, .bashrc→.zshrc
exec $SHELL -l

# 3) Ruby 4.0.5 — 미리 컴파일된 바이너리로
mise settings add idiomatic_version_file_enable_tools ruby   # 저장소의 .ruby-version 을 읽게
mise settings set ruby.compile false                         # 소스 빌드 대신 precompiled 만 사용
cd chaekgalpi && mise install ruby@4.0.5
ruby -v                                                      # ruby 4.0.5 ...

# 4) 젬 · DB · 시드
gem install foreman
bin/setup --skip-server
```

- Fedora 계열: `sudo dnf install -y gcc gcc-c++ make git curl pkgconf-pkg-config libyaml-devel sqlite sqlite-devel vips`
- Arch 계열: `sudo pacman -S --needed base-devel git curl libyaml sqlite libvips`
- Alpine 등 musl 배포판은 미리 컴파일된 Ruby 가 없습니다 — `ruby.compile` 줄을 빼고 소스 빌드로 두세요.
- `libvips` 는 손글씨 사진 축소·이미지 변형용입니다. 없어도 앱은 뜨며 원본을 그대로 쓰는 폴백으로 동작합니다.

#### macOS

```bash
# 1) 명령줄 개발 도구 · Homebrew(https://brew.sh) · 시스템 패키지
xcode-select --install                 # 이미 있으면 그냥 넘어갑니다
brew install git libvips               # SQLite 는 macOS 기본 포함

# 2) mise
brew install mise
echo 'eval "$(mise activate zsh)"' >> ~/.zshrc
exec $SHELL -l

# 3) Ruby 4.0.5 — 미리 컴파일된 바이너리로 (Apple Silicon)
mise settings add idiomatic_version_file_enable_tools ruby
mise settings set ruby.compile false
cd chaekgalpi && mise install ruby@4.0.5
ruby -v

# 4) 젬 · DB · 시드
gem install foreman
bin/setup --skip-server
```

- 미리 컴파일된 Ruby 는 **Apple Silicon(arm64)** 에만 있습니다. Intel 맥은 `ruby.compile` 줄을 빼고
  `brew install openssl@3 libyaml gmp autoconf` 를 먼저 설치하세요(소스 빌드, 수 분).
- Intel 맥은 젬도 일부를 직접 컴파일합니다 — `Gemfile.lock` 이 Apple Silicon·Linux 바이너리만 고정하고 있어
  `bundle install` 이 조금 더 걸립니다.

</details>

### 설치 확인 · 그 밖의 도구

```bash
ruby -v            # ruby 4.0.5 ...
bundle -v          # Bundler 4.x — Ruby 4.0 에 기본 포함
sqlite3 --version
git --version
```

| 도구       | 언제 필요한가                                                                                                                                                                                                                                                                                                                        |
| ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Docker** | [서버 빠른 시작](#서버-빠른-시작) 의 Docker 한 줄 실행을 쓸 때만. Ubuntu·WSL2: `sudo apt-get install -y docker.io docker-compose-v2 && sudo usermod -aG docker $USER`(재로그인). WSL2 는 추가로 `printf '[boot]\nsystemd=true\n' \| sudo tee -a /etc/wsl.conf` 후 PowerShell 에서 `wsl --shutdown`. macOS·Windows 는 Docker Desktop. |
| **Chrome** | `bin/rails test:system`(시스템 테스트)에만. 드라이버는 selenium 이 알아서 받습니다.                                                                                                                                                                                                                                                  |
| **JDK 17** | Android 셸을 빌드할 때만 — [`android/README.md`](android/README.md)                                                                                                                                                                                                                                                                  |

---

## 서버 빠른 시작

### 가장 쉬운 실행 — Docker 한 줄 (권장, 비밀키 불필요)

Ruby·Rails 설치 없이 **Docker 만 있으면** 소스코드를 그대로 실행할 수 있습니다 — Windows·macOS 는
Docker Desktop, Linux·WSL2 는 [서버 환경 설정](#설치-확인--그-밖의-도구) 의 Docker 항목. 개발 모드로 뜨며,
데모 데이터까지 채워집니다.

`compose.yaml` 이 있는 이 폴더에서 터미널(Windows 는 Docker Desktop 이면 PowerShell, WSL2 면 Ubuntu
터미널)을 열고 한 줄만 실행하면 됩니다.

```bash
docker compose up          # 빌드 + 데모 데이터 적재 + 서버 → http://localhost:3000
```

미리 만든 이미지를 받는 방식이 아니라 `Dockerfile.dev` 로 **그 자리에서 빌드**하므로,
최초 1회는 **인터넷 연결**이 필요하고 수 분~십수 분 걸립니다(두 번째 실행부터는 빠릅니다).
빌드가 끝난 뒤의 데모 데이터 적재는 `db/seeds/` 의 로컬 파일만 쓰므로 인터넷이 필요 없습니다.

서버가 뜨면 브라우저에서 **http://localhost:3000** 을 여세요. 로그인 화면 아래
**"🚀 바로 체험해 보기"** 버튼을 누르면 아이디·비밀번호 입력 없이 학생·담임 계정으로
바로 들어갑니다.

#### 그 다음부터 쓰는 명령

같은 폴더에서 실행합니다.

| 하고 싶은 것                     | 명령                         |
| -------------------------------- | ---------------------------- |
| 서버 정지 (데이터는 보존)        | `docker compose down`        |
| 빠른 재시작                      | `docker compose up -d`       |
| 로그 보기 (`Ctrl+C` 로 빠져나옴) | `docker compose logs -f app` |
| 소스를 고친 뒤 다시 빌드         | `docker compose up --build`  |
| 데이터까지 완전 초기화           | `docker compose down -v`     |

#### 막힐 때

| 증상                                                                | 해결                                                                                                                                                                              |
| ------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `docker: command not found` · `Cannot connect to the Docker daemon` | Docker 가 없거나 꺼져 있습니다. [서버 환경 설정](#설치-확인--그-밖의-도구) 의 Docker 항목대로 설치·기동하세요. WSL2 는 PowerShell 에서 `wsl --shutdown` 후 Ubuntu 를 다시 여세요. |
| 최초 실행이 20분을 넘김                                             | 다른 터미널에서 `docker compose logs -f app` 으로 진행 상황을 확인하세요. 최초 빌드는 원래 오래 걸립니다.                                                                         |
| `port is already allocated`                                         | 다른 프로그램이 3000 포트를 쓰는 중입니다. 그 프로그램을 끄고 다시 실행하세요.                                                                                                    |
| WSL2 에서 유난히 느림                                               | 소스가 `/mnt/c/...` 에 있으면 느립니다. [서버 환경 설정 › Windows](#windows) 대로 `~/` 아래로 옮기세요.                                                                           |

### 소스로 직접 실행 (Docker 없이)

먼저 [서버 환경 설정](#서버-환경-설정) 의 `./setup.sh` 를 한 번 끝내 두세요 — 그 안에서 `bin/setup`(젬·DB·시드)까지 끝납니다.

```bash
bin/dev        # 개발 서버 실행 (Rails 서버 + Tailwind watch) → http://localhost:3000
```

`setup.sh` 없이 Ruby 4.0.5 만 갖춘 상태라면:

```bash
bin/setup      # 의존성 설치 · DB 준비 · 시드 · 곧바로 bin/dev 까지
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

| credentials 키                            | 발급처                 | 켜지는 기능                       | 폴백                                          |
| ----------------------------------------- | ---------------------- | --------------------------------- | --------------------------------------------- |
| `claude.api_key`                          | Claude                 | OCR · 5축 첨삭 · 퀴즈 생성        | 규칙 기반 첨삭 / 오프라인 퀴즈 (OCR만 비활성) |
| `naver.client_id` · `naver.client_secret` | Naver Developers       | 도서 검색(단독 제공자)            | 로컬 카탈로그 LIKE 검색                       |
| `data4library.api_key`                    | 정보나루               | 인기대출 동기화                   | CSV 업로드                                    |
| `neis.api_key`                            | NEIS 교육정보 개방포털 | 학교 스냅샷 갱신(`schools:fetch`) | 커밋된 CSV 오프라인 시드                      |

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

---

## 사용자 역할

Pundit 정책으로 역할별 접근 권한을 관리하며, 일부 자원은 학교·학급 소속도 확인합니다.

| 역할                       | 주요 기능                                                                                                                                                                                                          |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **학생**                   | 독후감 작성·고쳐쓰기·공유, 독서 게임, 몬스터 도감·진화, 랭킹, 커뮤니티                                                                                                                                             |
| **담임교사**               | 검토 목록(모두·미검토·검토완료 필터), 5축 점수 조정·승인, 학생 관리(비번 재설정·포인트 부여), 미션·퀴즈 발행, 루브릭 설정, 문서 출력(표창장·가정통신문·독서 포트폴리오·학급 성장 리포트), 5축 원자료 엑셀 내보내기 |
| **총괄관리자(superadmin)** | 전용 `/admin` — 학교·사용자·도서·퀴즈·뱃지·상점·몬스터종 CRUD, 모더레이션, 전역 분석·설정                                                                                                                          |

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

## 프로젝트 구조 · 문서

```
app/
  controllers/   역할별 네임스페이스 (teacher · librarian · school_admin · admin · games)
  models/        report · book · monster_species · user_monster · quiz · badge · school ...
  services/      ai/ (claude_client · ocr · review · verify · quiz_draft)
                 books/ · library/ · monster_acquisition · ranking_board · reading_stats
  jobs/          ai_review_job · ocr_job (백그라운드 첨삭·OCR)
android/         Hotwire Native Android 셸 (Kotlin · Gradle, 웹앱과 동시 운영)
db/seeds/        monsters.yml (24라인 72폼)
lib/tasks/       monsters · badges · books · schools · quizzes rake 시드
```

| 문서                                                               | 내용                                                    |
| ------------------------------------------------------------------ | ------------------------------------------------------- |
| [`DESIGN.md`](DESIGN.md)                                           | 「책갈피」 디자인 시스템(토큰·컴포넌트·타이포·반응형)   |
| [`android/README.md`](android/README.md)                           | Android 빌드·서명·versionCode 정책                      |
| [`android/DEVICE_VERIFICATION.md`](android/DEVICE_VERIFICATION.md) | 실기기 검증 체크리스트(에뮬레이터 실측분과 미확인 구분) |
| [`NOTICE.md`](NOTICE.md)                                           | 폰트·이미지·데이터·AI 모델 출처 및 라이선스 표기        |
| [`TODO.md`](TODO.md)                                               | 남은 작업(배포·에셋·모니터링)                           |
