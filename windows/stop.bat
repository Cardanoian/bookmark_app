@echo off
title Chaekgalpi Stop
rem Stops the app containers. Data is preserved (docker volume).
wsl.exe -d Ubuntu -u root -- bash -c "cd /root/chaekgalpi 2>/dev/null && docker compose down"
echo.
echo Server stopped. Data is preserved; run setup-and-run.bat to start again.
echo (To also free WSL memory: run "wsl --shutdown" in PowerShell)
pause
