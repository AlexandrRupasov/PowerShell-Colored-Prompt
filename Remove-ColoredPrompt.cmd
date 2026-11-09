@echo off
setlocal EnableExtensions DisableDelayedExpansion
call "%~dp0Set-ColoredPrompt.cmd" -Action Uninstall %*
exit /b %ERRORLEVEL%
