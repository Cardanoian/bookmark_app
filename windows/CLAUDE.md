# windows/ — Windows 원클릭 설치·실행 스크립트

Windows 10/11 PC에서 **더블클릭 한 번**으로 WSL2 → Ubuntu → Docker 설치와 앱 기동
(`docker compose up`)까지 자동 진행하는 부트스트랩 스크립트 모음이다.
앱 런타임과는 분리된 심사·시연 PC 세팅 전용. (사용자 안내: [docs/JUDGE_RUN_LOCAL.md](../docs/JUDGE_RUN_LOCAL.md))

## 파일

| 파일 | 역할 |
|------|------|
| `setup-and-run.bat` | **진입점**. 관리자 권한(UAC) 승격 후 `setup.ps1` 실행. 멱등 — 재실행 시 끝난 단계는 건너뛰므로 평상시 "실행 버튼"으로도 쓴다 |
| `setup.ps1` | 본체(Windows PowerShell 5.1 호환). WSL2 설치(필요 시 HKCU RunOnce 로 재부팅 후 자동 재개) → Ubuntu 설치(`--no-launch`, 첫 실행 OOBE 필요 시 안내 후 종료) → `setup-wsl.sh` 2단계 호출 → 완료 후 브라우저 오픈 |
| `setup-wsl.sh` | Ubuntu(root) 내부용. `provision`(apt 로 `docker.io`+`docker-compose-v2` 설치, `/etc/wsl.conf` 에 systemd 활성) / `run`(소스 동기화 → `docker compose up -d --build` → `/up` 헬스체크 최대 20분 대기) |
| `stop.bat` | `docker compose down` — 데이터(볼륨)는 보존 |
| `logs.bat` | `docker compose logs -f app` |

## 동작 메모

- **소스 결정**: 이 폴더의 상위(리포 루트)에 `compose.yaml` 이 있으면 그 소스를 WSL 홈(`/root/chaekgalpi`)으로 복사(zip 배포 시나리오), 없으면 GitHub 에서 `--depth 1` clone. SQLite I/O 성능·잠금 문제 때문에 `/mnt/c` 에서 직접 돌리지 않는다.
- **Docker Desktop 을 쓰지 않는다**: Ubuntu 안의 Docker Engine(apt)이라 라이선스·수동 설치 없이 전 과정을 스크립트화할 수 있다. 실행되는 컨테이너는 리포의 `Dockerfile.dev`+`compose.yaml`(= `bin/docker-dev-entrypoint`, 개발 모드·무키 폴백·데모 시드) 그대로다.
- **개행/인코딩 계약**: `.bat`·`.ps1` 은 CRLF(`.ps1` 은 UTF-8 **BOM** — PowerShell 5.1 한글 출력 요건), `.sh` 는 LF. 루트 `.gitattributes` 로 강제하고, 실행 시에도 `tr -d '\r'` 로 한 번 더 방어한다.
- WSL2 최초 설치 PC는 중간 **재부팅 1회**가 필요하며, 재부팅 후 로그인하면 RunOnce 가 bat 를 다시 띄워 이어서 진행한다.

---
> ⚠️ **유지보수 규칙**: 이 폴더의 파일이 추가·삭제되거나 역할이 바뀌면 이 CLAUDE.md 와 루트 [CLAUDE.md](../CLAUDE.md) 인덱스를 함께 갱신하세요.
