# windows/ — Windows 원클릭 설치·실행 스크립트

Windows 10/11 PC에서 **더블클릭 한 번**으로 WSL2 → Ubuntu → Docker 설치와 앱 기동
(`docker compose up`)까지 자동 진행하는 부트스트랩 스크립트 모음이다.
앱 런타임과는 분리된 심사·시연 PC 세팅 전용. (사용자 안내: [docs/JUDGE_RUN_LOCAL.md](../docs/JUDGE_RUN_LOCAL.md))

## 파일

| 파일 | 역할 |
|------|------|
| `setup-and-run.bat` | **진입점**. 관리자 권한(UAC) 승격 후 `setup.ps1` 실행. 멱등 — 재실행 시 끝난 단계는 건너뛰므로 평상시 "실행 버튼"으로도 쓴다. 승격 재귀는 `elevated` 인자로 1회 제한하고, 모든 실패 경로에서 원인·대안을 출력한 뒤 `pause` 한다 |
| `setup.ps1` | 본체(Windows PowerShell 5.1 호환). WSL2 설치(필요 시 HKCU RunOnce 로 재부팅 후 자동 재개) → Ubuntu 설치(`--no-launch`, 첫 실행 OOBE 필요 시 안내 후 종료) → `setup-wsl.sh` 2단계 호출 → 완료 후 브라우저 오픈 |
| `setup-wsl.sh` | Ubuntu(root) 내부용. `provision`(apt 로 `docker.io`+`docker-compose-v2` 설치, `/etc/wsl.conf` 에 systemd 활성) / `run`(소스 동기화 → `docker compose up -d --build` → `/up` 헬스체크 최대 20분 대기) |
| `stop.bat` | `docker compose down` — 데이터(볼륨)는 보존 |
| `logs.bat` | `docker compose logs -f app` |
| `차단될때_읽어주세요.txt` | 사용자용 안내문. 스마트 앱 컨트롤/SmartScreen 이 bat 를 막을 때의 해결 1(차단 해제)·2(Docker Desktop)·3(스크립트 없이 붙여넣기 명령 4줄) |

## 동작 메모

- **소스 결정**: 이 폴더의 상위(리포 루트)에 `compose.yaml` 이 있으면 그 소스를 WSL 홈(`/root/chaekgalpi`)으로 복사(zip 배포 시나리오), 없으면 GitHub 에서 `--depth 1` clone. SQLite I/O 성능·잠금 문제 때문에 `/mnt/c` 에서 직접 돌리지 않는다.
- **Docker Desktop 을 쓰지 않는다**: Ubuntu 안의 Docker Engine(apt)이라 라이선스·수동 설치 없이 전 과정을 스크립트화할 수 있다. 실행되는 컨테이너는 리포의 `Dockerfile.dev`+`compose.yaml`(= `bin/docker-dev-entrypoint`, 개발 모드·무키 폴백·데모 시드) 그대로다.
- **개행/인코딩 계약**: `.bat`·`.ps1`·`.txt` 는 CRLF, `.sh` 는 LF (루트 `.gitattributes` 로 강제, 실행 시에도 `tr -d '\r'` 로 한 번 더 방어). 인코딩은 셋 다 UTF-8 이되 **BOM 유무가 다르다** — `.ps1`·`.txt` 는 **BOM 포함**(PowerShell 5.1 한글 출력 / 메모장 한글 판독 요건), `.bat` 은 cmd 가 BOM 을 명령으로 읽어버리므로 **BOM 없이** 쓰고 대신 첫 줄에서 `chcp 65001` 로 콘솔 코드페이지를 맞춘다.
- **관리자 권한 판정**: `.bat`·`.ps1` 모두 `net session` 이 아니라 **`fltmc`** 의 종료 코드로 본다. `net session` 은 Server 서비스가 꺼진 PC 에서 승격 후에도 실패해 무한 재승격(겉보기엔 "아무 일도 안 일어남")을 만든다. `.ps1` 은 추가로 `[Security.Principal.*]` 조회를 쓰지 않는데, 스마트 앱 컨트롤이 켜진 PC 의 **제한 언어 모드(CLM)** 에서 .NET 타입 접근이 막히기 때문이다(감지 시 `$ExecutionContext.SessionState.LanguageMode` 로 안내 출력).
- **스마트 앱 컨트롤(SAC)·SmartScreen 차단**: zip 배포 시 풀린 파일에 MotW(`Zone.Identifier`)가 붙어 서명 없는 `.bat`/`.ps1` 이 실행 전에 차단된다. **스크립트 안에서는 자기 자신의 차단을 풀 수 없으므로**(차단된 뒤라 실행 자체가 안 됨) 해결은 문서·안내문 경로로만 제공한다 → `차단될때_읽어주세요.txt`, [docs/JUDGE_RUN_LOCAL.md](../docs/JUDGE_RUN_LOCAL.md) 방법 0 하위 절. WSL 내부의 `setup-wsl.sh` 는 SAC 적용 대상이 아니므로 최후 경로(붙여넣기 명령)로 재사용한다.
- WSL2 최초 설치 PC는 중간 **재부팅 1회**가 필요하며, 재부팅 후 로그인하면 RunOnce 가 bat 를 다시 띄워 이어서 진행한다.

---
> ⚠️ **유지보수 규칙**: 이 폴더의 파일이 추가·삭제되거나 역할이 바뀌면 이 CLAUDE.md 와 루트 [CLAUDE.md](../CLAUDE.md) 인덱스를 함께 갱신하세요.
