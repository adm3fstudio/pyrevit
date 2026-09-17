@echo off
setlocal
REM Relatorio do estado do pyRevit nesta maquina (nao altera nada).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Diagnostico.ps1" %*
echo.
pause
