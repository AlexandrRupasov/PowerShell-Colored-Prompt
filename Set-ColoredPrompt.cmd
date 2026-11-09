@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "SCRIPT=%~dp0Set-ColoredPrompt.ps1"
if not exist "%SCRIPT%" exit /b 2
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
set "RESULT=%ERRORLEVEL%"
if not defined COLORED_PROMPT_NO_PAUSE pause
exit /b %RESULT%
