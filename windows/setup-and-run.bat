@echo off
chcp 65001 >nul
setlocal
title Chaekgalpi Setup
cd /d "%~dp0"
rem ------------------------------------------------------------
rem  Chaekgalpi (bookmark_app) one-click setup and run
rem  Installs WSL2 + Ubuntu + Docker, then starts the app at
rem  http://localhost:3000  (details: docs/JUDGE_RUN_LOCAL.md)
rem  Safe to run again anytime: finished steps are skipped.
rem  Encoding contract: UTF-8 (no BOM) + CRLF, with chcp 65001 above.
rem ------------------------------------------------------------

rem 관리자 여부는 관리자 전용 명령인 fltmc 로 판정한다.
rem  ('net session' 은 Server 서비스가 꺼진 PC 에서 승격 후에도 실패해서
rem   승격 → 재승격 → ... 무한 루프로 "아무 일도 안 일어남" 처럼 보인다.)
fltmc >nul 2>&1
if "%errorlevel%"=="0" goto :run

if /i "%~1"=="elevated" (
  echo.
  echo [오류] 관리자 권한을 얻지 못했습니다.
  echo.
  echo   시작 단추에서 "PowerShell" 을 찾아 마우스 오른쪽 - [관리자 권한으로 실행]
  echo   한 뒤, 아래 한 줄을 붙여넣어 주세요.
  echo.
  echo      powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1"
  echo.
  pause
  exit /b 1
)

echo 관리자 권한을 요청합니다. UAC 창이 뜨면 [예] 를 눌러 주세요...
powershell -NoProfile -Command "try { Start-Process -Verb RunAs -FilePath '%~f0' -ArgumentList 'elevated'; exit 0 } catch { exit 1 }"
if not "%errorlevel%"=="0" (
  echo.
  echo [오류] 관리자 권한 요청이 취소되었거나 차단되었습니다.
  echo        새 창이 열리지 않았다면 windows\차단될때_읽어주세요.txt 를 읽어 주세요.
  echo.
  pause
)
exit /b

:run
echo.
echo 설치·실행 스크립트를 시작합니다. 이 창을 닫지 마세요.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1"
set "RC=%errorlevel%"
if not "%RC%"=="0" (
  echo.
  echo [오류] 설치 스크립트가 오류 코드 %RC% 로 끝났습니다.
  echo        바로 위에 표시된 메시지를 확인해 주세요.
  echo        아무 메시지도 없이 끝났다면 스크립트 실행이 차단된 것이므로
  echo        windows\차단될때_읽어주세요.txt 의 "해결 3" 을 따라 주세요.
)
echo.
pause
