@echo off
setlocal
REM Gera o pacote da extensao 3fstudio na pasta deste arquivo.
set "PS1=%~dp0Export-PyRevitPackage.ps1"

if not exist "%PS1%" (
  echo [ERRO] Export-PyRevitPackage.ps1 nao encontrado.
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" -OutputPath "%~dp0" %*
set "RC=%ERRORLEVEL%"

echo.
if "%RC%"=="0" (echo Pacote gerado.) else (echo Falhou com erro %RC%.)
pause
exit /b %RC%
