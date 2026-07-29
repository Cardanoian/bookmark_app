@echo off
setlocal
title Chaekgalpi Setup
rem ------------------------------------------------------------
rem  Chaekgalpi (bookmark_app) one-click setup and run
rem  Installs WSL2 + Ubuntu + Docker, then starts the app at
rem  http://localhost:3000  (details: docs/JUDGE_RUN_LOCAL.md)
rem  Safe to run again anytime: finished steps are skipped.
rem ------------------------------------------------------------

net session >nul 2>&1
if not "%errorlevel%"=="0" (
  echo Requesting administrator privileges (UAC)...
  powershell -NoProfile -Command "Start-Process -Verb RunAs -FilePath '%~f0'"
  exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1"

echo.
pause
