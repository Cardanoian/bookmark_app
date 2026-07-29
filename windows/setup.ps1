# setup.ps1 - 책갈피(Chaekgalpi) Windows 원클릭 설치·실행 본체.
# setup-and-run.bat 가 관리자 권한으로 호출한다. (Windows PowerShell 5.1 호환)
#
# 진행 단계:
#   1) WSL2 미설치면 설치 (필요 시 재부팅 후 RunOnce 로 자동 재개)
#   2) Ubuntu 배포판 설치
#   3) Ubuntu 안에 Docker 설치 (setup-wsl.sh provision)
#   4) 소스 동기화 + docker compose up + 헬스체크 (setup-wsl.sh run)
#   5) 브라우저로 http://localhost:3000 열기

$ErrorActionPreference = "Continue"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$env:WSL_UTF8 = "1"

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$BatPath    = Join-Path $ScriptDir "setup-and-run.bat"
$Distro     = "Ubuntu"
$RunOnceKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce"

function Step([string]$msg) { Write-Host ""; Write-Host "== $msg" -ForegroundColor Cyan }
function Fail([string]$msg) { Write-Host ""; Write-Host "[오류] $msg" -ForegroundColor Red; exit 1 }

# ── 0. 사전 점검 ─────────────────────────────────────────────
Write-Host "책갈피(Chaekgalpi) 설치·실행을 시작합니다." -ForegroundColor Green

# 관리자 판정은 .NET 타입 대신 관리자 전용 명령의 종료 코드로 한다.
#  · [Security.Principal.*] 조회는 스마트 앱 컨트롤이 켜진 PC 의 제한 언어
#    모드(Constrained Language Mode)에서 막혀 승격됐는데도 실패로 읽힌다.
#  · net session 은 Server 서비스가 꺼진 PC 에서 관리자여도 실패한다.
function Test-Admin {
    if (Get-Command fltmc.exe -ErrorAction SilentlyContinue) { & fltmc.exe *> $null }
    else { & net.exe session *> $null }
    return ($LASTEXITCODE -eq 0)
}
if (-not (Test-Admin)) { Fail "관리자 권한이 필요합니다. setup-and-run.bat 를 마우스 오른쪽 → '관리자 권한으로 실행' 해 주세요." }

if ($ExecutionContext.SessionState.LanguageMode -ne "FullLanguage") {
    Write-Host "[안내] 이 PC 는 보안 정책(스마트 앱 컨트롤 등)으로 스크립트가 제한 모드로 실행됩니다." -ForegroundColor Yellow
    Write-Host "       중간에 멈추면 windows\차단될때_읽어주세요.txt 의 '해결 3' 을 사용해 주세요."
}

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    Fail "이 Windows 에는 WSL 명령이 없습니다. Windows 10 2004(빌드 19041) 이상으로 업데이트한 뒤 다시 실행해 주세요."
}

# ── 1. WSL2 ──────────────────────────────────────────────────
wsl.exe --status *> $null
if ($LASTEXITCODE -ne 0) {
    Step "WSL2 설치 중... (몇 분 걸릴 수 있습니다)"
    wsl.exe --install --no-distribution
    if ($LASTEXITCODE -ne 0) {
        wsl.exe --install -d $Distro --no-launch
        if ($LASTEXITCODE -ne 0) {
            Fail "WSL2 설치에 실패했습니다. BIOS 에서 가상화(VT-x/AMD-V)가 켜져 있는지, Windows 업데이트가 최신인지 확인 후 다시 실행해 주세요."
        }
    }
    # 재부팅 후 로그인하면 이 설치가 자동으로 이어지도록 예약
    Set-ItemProperty -Path $RunOnceKey -Name "ChaekgalpiSetup" -Value "cmd /c start `"`" `"$BatPath`""
    Write-Host ""
    Write-Host "WSL2 구성 요소가 설치되었습니다. 계속하려면 재부팅이 필요합니다." -ForegroundColor Yellow
    Write-Host "재부팅 후 로그인하면 설치가 자동으로 이어집니다."
    $ans = Read-Host "지금 바로 재부팅할까요? (Y/N)"
    if ($ans -match "^[Yy]") { Restart-Computer -Force }
    exit 0
}

wsl.exe --set-default-version 2 *> $null

# ── 2. Ubuntu ────────────────────────────────────────────────
function Get-Distros {
    $list = @()
    $raw = wsl.exe -l -q 2>$null
    foreach ($line in @($raw)) {
        $name = ("$line" -replace "`0", "").Trim()
        if ($name) { $list += $name }
    }
    return $list
}

if ((Get-Distros) -notcontains $Distro) {
    Step "Ubuntu 설치 중..."
    wsl.exe --install -d $Distro --no-launch
    if (($LASTEXITCODE -ne 0) -or ((Get-Distros) -notcontains $Distro)) {
        Fail "Ubuntu 설치에 실패했습니다. 관리자 PowerShell 에서 'wsl --install -d Ubuntu' 를 직접 실행해 보고 다시 시도해 주세요."
    }
}

wsl.exe -d $Distro -u root -e true *> $null
if ($LASTEXITCODE -ne 0) {
    Step "Ubuntu 첫 실행(초기 설정)이 필요합니다"
    Write-Host "잠시 후 열리는 Ubuntu 창에서 안내에 따라 사용자 이름/암호를 만든 뒤,"
    Write-Host "그 창을 닫고 setup-and-run.bat 를 다시 실행해 주세요."
    Start-Process cmd.exe -ArgumentList "/c", "wsl -d $Distro"
    exit 0
}

# ── 3. Ubuntu 내부 구성 (Docker 등) ──────────────────────────
$ShWin = Join-Path $ScriptDir "setup-wsl.sh"
$ShWsl = (@(wsl.exe -d $Distro -u root -e wslpath -a $ShWin) | Select-Object -First 1)
if (-not $ShWsl) { Fail "경로 변환(wslpath)에 실패했습니다." }
$ShWsl = "$ShWsl".Trim()

Step "Ubuntu 안에 Docker 등 필요한 도구 설치 중..."
wsl.exe -d $Distro -u root -- bash -c "tr -d '\r' < '$ShWsl' > /root/chaekgalpi-setup.sh && bash /root/chaekgalpi-setup.sh provision"
if ($LASTEXITCODE -ne 0) { Fail "Ubuntu 내부 도구 설치에 실패했습니다. 인터넷 연결을 확인한 뒤 다시 실행해 주세요." }

wsl.exe --terminate $Distro *> $null   # systemd 설정 반영을 위해 한 번 재시작

# ── 4. 소스 위치 결정 ────────────────────────────────────────
# 이 폴더(windows/)의 상위가 리포 루트면 그 소스를 쓰고(zip 배포), 아니면 GitHub 에서 clone.
$RepoRoot = Split-Path -Parent $ScriptDir
$SrcWsl = ""
if (Test-Path (Join-Path $RepoRoot "compose.yaml")) {
    $SrcWsl = "$(@(wsl.exe -d $Distro -u root -e wslpath -a $RepoRoot) | Select-Object -First 1)".Trim()
}

# ── 5. 빌드 & 실행 ───────────────────────────────────────────
Step "앱 빌드·데모 데이터 적재·서버 시작 (최초 1회는 수 분~십수 분)"
wsl.exe -d $Distro -u root -- bash -c "SRC_DIR='$SrcWsl' bash /root/chaekgalpi-setup.sh run"
if ($LASTEXITCODE -ne 0) { Fail "앱 실행에 실패했습니다. windows\logs.bat 로 로그를 확인해 주세요." }

Step "완료!"
Write-Host "브라우저에서 http://localhost:3000 을 엽니다. (로그인 계정: docs/JUDGE_GUIDE.md)"
Write-Host "  · 서버 정지 : windows\stop.bat"
Write-Host "  · 로그 보기 : windows\logs.bat"
Write-Host "  · 다시 실행 : windows\setup-and-run.bat  (이미 설치된 단계는 건너뜀)"
Start-Process "http://localhost:3000"
exit 0
