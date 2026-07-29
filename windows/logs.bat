@echo off
title Chaekgalpi Logs
echo Showing app logs. Press Ctrl+C to quit.
echo.
wsl.exe -d Ubuntu -u root -- bash -c "cd /root/chaekgalpi 2>/dev/null && docker compose logs -f app"
pause
