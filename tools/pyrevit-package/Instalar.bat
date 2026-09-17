@echo off
setlocal
REM Instalador do pacote pyRevit - clique duplo neste arquivo.
set "PKG=%~dp0"
set "PS1=%PKG%tools\Install-PyRevitPackage.ps1"

if not exist "%PS1%" (
  echo [ERRO] tools\Install-PyRevitPackage.ps1 nao encontrado.
  echo Extraia o .zip por completo antes de rodar este instalador.
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" -PackagePath "%PKG%." %*
set "RC=%ERRORLEVEL%"

echo.
if "%RC%"=="0" (echo Instalacao concluida.) else (echo Instalacao terminou com erro %RC%.)
pause
exit /b %RC%
